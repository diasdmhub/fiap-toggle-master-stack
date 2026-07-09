"""
Lambda de self-healing do ToggleMaster.

Recebe o webhook de um alerta "firing" do Grafana (contact point tipo
`webhook`), valida um segredo compartilhado, aplica um cooldown por
serviço via DynamoDB (para não entrar em loop de restart) e, se tudo
estiver ok, reinicia o Deployment correspondente no EKS fazendo um PATCH
direto na API do Kubernetes (equivalente a `kubectl rollout restart`).

Só usa boto3/botocore (já incluídos no runtime da Lambda) + biblioteca
padrão do Python. Nenhuma dependência externa/layer é necessária.
"""

import base64
import hmac
import json
import logging
import os
import ssl
import time
import urllib.request
import urllib.error

import boto3
import botocore.session
from botocore.signers import RequestSigner

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# ---------------------------------------------------------------------------
# Configuração via variáveis de ambiente (definidas no Terraform)
# ---------------------------------------------------------------------------
CLUSTER_NAME = os.environ["CLUSTER_NAME"]
CLUSTER_ENDPOINT = os.environ["CLUSTER_ENDPOINT"]
CLUSTER_CA_B64 = os.environ["CLUSTER_CA"]
NAMESPACE = os.environ["NAMESPACE"]
ALLOWED_DEPLOYMENTS = set(os.environ["ALLOWED_DEPLOYMENTS"].split(","))
WEBHOOK_USERNAME = os.environ["WEBHOOK_USERNAME"]
WEBHOOK_PASSWORD = os.environ["WEBHOOK_PASSWORD"]
COOLDOWN_SECONDS = int(os.environ["COOLDOWN_SECONDS"])
COOLDOWN_TABLE = os.environ["COOLDOWN_TABLE"]
AWS_REGION = os.environ["AWS_REGION"]

dynamodb = boto3.resource("dynamodb")
cooldown_table = dynamodb.Table(COOLDOWN_TABLE)

# Escreve o CA cert em /tmp uma vez por execution environment (fica em cache
# entre invocações "quentes" da mesma instância do Lambda).
_CA_PATH = "/tmp/eks-ca.pem"


def _write_ca_file():
    if not os.path.exists(_CA_PATH):
        with open(_CA_PATH, "wb") as f:
            f.write(base64.b64decode(CLUSTER_CA_B64))
    return _CA_PATH


def _get_eks_token():
    """
    Gera um bearer token no mesmo esquema usado por `aws eks get-token` /
    aws-iam-authenticator: uma URL pré-assinada (SigV4) de
    sts:GetCallerIdentity, com o header x-k8s-aws-id, codificada em base64.
    """
    session = botocore.session.get_session()
    sts_client = session.create_client("sts", region_name=AWS_REGION)
    service_id = sts_client.meta.service_model.service_id

    signer = RequestSigner(
        service_id,
        AWS_REGION,
        "sts",
        "v4",
        session.get_credentials(),
        session.get_component("event_emitter"),
    )

    params = {
        "method": "GET",
        "url": f"https://sts.{AWS_REGION}.amazonaws.com/?Action=GetCallerIdentity&Version=2011-06-15",
        "body": {},
        "headers": {"x-k8s-aws-id": CLUSTER_NAME},
        "context": {},
    }

    signed_url = signer.generate_presigned_url(
        params, region_name=AWS_REGION, expires_in=60, operation_name=""
    )

    token = base64.urlsafe_b64encode(signed_url.encode("utf-8")).decode("utf-8").rstrip("=")
    return f"k8s-aws-v1.{token}"


def _check_and_set_cooldown(deployment_name: str) -> bool:
    """
    Retorna True se o serviço pode ser reiniciado agora (ou seja, não houve
    restart nos últimos COOLDOWN_SECONDS). Usa PutItem condicional no
    DynamoDB para evitar restarts concorrentes/duplicados.
    """
    now = int(time.time())
    try:
        cooldown_table.put_item(
            Item={
                "service_name": deployment_name,
                "last_restart": now,
                "ttl": now + COOLDOWN_SECONDS,
            },
            ConditionExpression="attribute_not_exists(service_name) OR last_restart < :cutoff",
            ExpressionAttributeValues={":cutoff": now - COOLDOWN_SECONDS},
        )
        logger.info("Cooldown OK para '%s', prosseguindo com o restart", deployment_name)
        return True
    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
        logger.info("'%s' em cooldown (restart recente), pulando", deployment_name)
        return False


def _restart_deployment(deployment_name: str):
    """
    Faz o equivalente a `kubectl rollout restart deployment/<nome>`:
    um strategic-merge-patch que atualiza a annotation
    kubectl.kubernetes.io/restartedAt no template do pod, forçando o
    rolling restart.
    """
    token = _get_eks_token()
    ca_path = _write_ca_file()

    restarted_at = time.strftime("%Y-%m-%dT%H:%M:%S%z", time.gmtime())
    patch_body = json.dumps(
        {
            "spec": {
                "template": {
                    "metadata": {
                        "annotations": {
                            "kubectl.kubernetes.io/restartedAt": restarted_at
                        }
                    }
                }
            }
        }
    ).encode("utf-8")

    url = f"{CLUSTER_ENDPOINT}/apis/apps/v1/namespaces/{NAMESPACE}/deployments/{deployment_name}"

    logger.info("Enviando PATCH para %s", url)

    request = urllib.request.Request(
        url,
        data=patch_body,
        method="PATCH",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/strategic-merge-patch+json",
            "Accept": "application/json",
        },
    )

    ssl_context = ssl.create_default_context(cafile=ca_path)

    with urllib.request.urlopen(request, context=ssl_context, timeout=10) as response:
        logger.info("PATCH em '%s' retornou HTTP %s", deployment_name, response.status)
        return response.status, response.read().decode("utf-8")


def _valid_basic_auth(headers: dict) -> bool:
    """
    O contact point webhook do Grafana não suporta headers arbitrários -
    só Basic Auth ou um header Authorization com esquema customizado, não
    ambos ao mesmo tempo. Usamos Basic Auth aqui.
    """
    auth_header = headers.get("authorization", "")
    if not auth_header.startswith("Basic "):
        logger.warning(
            "Auth rejeitada: header 'Authorization' ausente ou sem esquema "
            "Basic. Headers recebidos: %s",
            sorted(headers.keys()),
        )
        return False

    try:
        decoded = base64.b64decode(auth_header[len("Basic "):]).decode("utf-8")
        username, _, password = decoded.partition(":")
    except (ValueError, UnicodeDecodeError):
        logger.warning("Auth rejeitada: não foi possível decodificar o header Basic Auth")
        return False

    # Comparação em tempo constante para evitar timing attack
    user_ok = hmac.compare_digest(username, WEBHOOK_USERNAME)
    pass_ok = hmac.compare_digest(password, WEBHOOK_PASSWORD)
    if not (user_ok and pass_ok):
        logger.warning(
            "Auth rejeitada: credenciais não conferem (username_ok=%s, password_ok=%s)",
            user_ok, pass_ok,
        )
    return user_ok and pass_ok


def lambda_handler(event, context):
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}

    if not _valid_basic_auth(headers):
        return {"statusCode": 401, "body": json.dumps({"error": "unauthorized"})}

    logger.info("Auth OK. Payload recebido: %s", event.get("body"))

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return {"statusCode": 400, "body": json.dumps({"error": "invalid json"})}

    # Payload padrão do Grafana unified alerting webhook: lista de "alerts"
    alerts = body.get("alerts", [])
    logger.info("Processando %d alerta(s)", len(alerts))
    results = []

    for alert in alerts:
        if alert.get("status") != "firing":
            logger.info("Ignorando alerta com status '%s' (não é 'firing')", alert.get("status"))
            continue

        labels = alert.get("labels", {})
        deployment_name = labels.get("deployment")

        if not deployment_name or deployment_name not in ALLOWED_DEPLOYMENTS:
            logger.warning(
                "Deployment '%s' não está na allowlist %s, pulando",
                deployment_name, sorted(ALLOWED_DEPLOYMENTS),
            )
            results.append({"deployment": deployment_name, "action": "skipped_not_allowed"})
            continue

        if not _check_and_set_cooldown(deployment_name):
            results.append({"deployment": deployment_name, "action": "skipped_cooldown"})
            continue

        try:
            status, _ = _restart_deployment(deployment_name)
            logger.info("'%s' reiniciado com sucesso (HTTP %s)", deployment_name, status)
            results.append({"deployment": deployment_name, "action": "restarted", "k8s_status": status})
        except urllib.error.HTTPError as e:
            error_detail = f"{e.code} {e.read().decode('utf-8', 'ignore')}"
            logger.error("Falha ao reiniciar '%s': %s", deployment_name, error_detail)
            results.append({
                "deployment": deployment_name,
                "action": "error",
                "detail": error_detail,
            })

    logger.info("Resultado final: %s", results)
    return {"statusCode": 200, "body": json.dumps({"results": results})}