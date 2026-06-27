terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.1"
    }
  }
}


# Namespace compartilhado para toda a stack de monitoração
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}


# 1. kube-prometheus-stack
#    Inclui: Prometheus, Grafana, Node Exporter e kube-state-metrics
resource "helm_release" "prometheus_stack" {
  name       = "prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.prometheus_chart_version != "" ? var.prometheus_chart_version : null
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  # ServerSideApply necessário devido ao tamanho das anotações dos CRDs
  set = [
    {
      name  = "crds.enabled"
      value = "true"
    }
  ]

  values = [
    yamlencode({
      # Grafana
      grafana = {
        enabled       = true
        adminPassword = var.grafana_pass

        # Datasources provisionados automaticamente
        additionalDataSources = [
          {
            name      = "Loki"
            type      = "loki"
            uid       = "loki"
            url       = "http://loki-gateway.monitoring.svc.cluster.local"
            access    = "proxy"
            isDefault = false
            jsonData = { maxLines = 1000 }
          },
          {
            name      = "Tempo"
            type      = "tempo"
            uid       = "tempo"
            url       = "http://tempo.monitoring.svc.cluster.local:3200"
            access    = "proxy"
            isDefault = false
            jsonData = {
              # Permite pular do trace direto para os logs correlatos no Loki
              tracesToLogsV2 = {
                datasourceUid = "loki"
                spanStartTimeShift = "-5m"
                spanEndTimeShift   = "5m"
                filterByTraceID    = true
                tags = [{ key = "service.name", value = "service_name" }]
              }
              serviceMap = { datasourceUid = "prometheus" }
              nodeGraph  = { enabled = true }
            }
          }
        ]

        # Dashboards prontos importados do Grafana Labs
        dashboardProviders = {
          "dashboardproviders.yaml" = {
            apiVersion = 1
            providers = [{
              name            = "default"
              orgId           = 1
              folder          = ""
              type            = "file"
              disableDeletion = false
              editable        = true
              options = { path = "/var/lib/grafana/dashboards/default" }
              }]
          }
        }

        dashboards = {
          default = {
            kubernetes-cluster = {
              gnetId     = 7249
              revision   = 1
              datasource = "Prometheus"
            }
            node-exporter = {
              gnetId     = 1860
              revision   = 37
              datasource = "Prometheus"
            }
            k8s-pods = {
              gnetId     = 6417
              revision   = 1
              datasource = "Prometheus"
            }
          }
        }

        service = { type = var.grafana_service_type }

        persistence = { enabled = false }
      }

      # Prometheus
      prometheus = {
        prometheusSpec = {
          # Aceita ServiceMonitors de qualquer namespace (inclui toggle)
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          ruleSelectorNilUsesHelmValues           = false

          # Habilita recebimento via remote_write (usado pelo OTel Collector)
          enableRemoteWriteReceiver = true

          # Habilita recebimento OTLP direto
          enableOTLPReceiver = true

          retention     = "5d"
          retentionSize = "5GB"

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources   = { requests = { storage = "20Gi" } }
              }
            }
          }

          resources = {
            requests = { cpu = "200m", memory = "512Mi" }
            limits   = { cpu = "1000m", memory = "2Gi" }
          }
        }
      }

      # Alertmanager
      alertmanager = { enabled = false }

      nodeExporter     = { enabled = true }
      kubeStateMetrics = { enabled = true }
    })
  ]

  # ServerSideApply para evitar erro "metadata.annotations: Too long"
  force_update  = false
  timeout       = 600
  wait          = true
  recreate_pods = false

  lifecycle {
    ignore_changes = [
      # Evita redeploy quando o Grafana atualiza o ConfigMap das dashboards
      set,
    ]
  }

  depends_on = [kubernetes_namespace_v1.monitoring]
}


# 2. Loki
#    Centraliza e armazena logs do cluster
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_chart_version != "" ? var.loki_chart_version : null
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    yamlencode({
      # Modo SingleBinary: simples para lab/staging
      # Para produção, é melhor o deploymentMode = "SimpleScalable" com storage S3
      deploymentMode = "SingleBinary"

      loki = {
        auth_enabled = false

        commonConfig = { replication_factor = 1 }

        schemaConfig = {
          configs = [{
            from         = "2024-01-01"
            store        = "tsdb"
            object_store = "filesystem"
            schema       = "v13"
            index        = { prefix = "loki_index_", period = "24h" }
          }]
        }

        storage = { type = "filesystem" }

        # Habilita recebimento via OTLP HTTP
        limits_config = {
          allow_structured_metadata = true
          volume_enabled            = true
          otlp_config = {
            resource_attributes = {
              attributes_config = [{
                action = "index_label"
                attributes = [
                  "k8s.namespace.name",
                  "k8s.pod.name",
                  "k8s.container.name",
                  "service.name"
                ]
              }]
            }
          }
        }
      }

      singleBinary = {
        replicas = 1
        persistence = {
          enabled = true
          size    = "10Gi"
        }
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "500m", memory = "1Gi" }
        }
      }

      # Gateway HTTP - endpoint único para leitura/escrita
      gateway = {
        enabled = true
        service = { type = "ClusterIP" }
      }

      # monitoring = {
      #   serviceMonitor = {
      #     enabled = true
      #     labels = {
      #       # Label que o kube-prometheus-stack usa para descobrir ServiceMonitors
      #       release = "prometheus-stack"
      #     }
      #   }
      #   selfMonitoring = {
      #     enabled = false
      #     grafanaAgent = { installOperator = false }
      #   }
      # }

      # Componentes desnecessários no modo SingleBinary
      # desabilita o Memcached (chunks-cache)
      chunksCache = { enabled = false }
      resultsCache = { enabled = false }
      
      backend    = { replicas = 0 }
      read       = { replicas = 0 }
      write      = { replicas = 0 }
      lokiCanary = { enabled = false }
      test       = { enabled = false }
    })
  ]

  timeout = 300
  wait    = true

  depends_on = [kubernetes_namespace_v1.monitoring]
}


# 3. Grafana Tempo
#    Armazena e indexa os traces distribuídos (modo single-binary,
#    mesmo padrão usado para o Loki: simples para lab/staging)
resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = var.tempo_chart_version != "" ? var.tempo_chart_version : null
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    yamlencode({
      tempo = {
        retention = "120h" # 5 dias, alinhado com a retenção do Prometheus

        # Apenas o receiver OTLP é necessário; o OTel Collector é o único emissor
        receivers = {
          otlp = {
            protocols = {
              grpc = { endpoint = "0.0.0.0:4317" }
              http = { endpoint = "0.0.0.0:4318" }
            }
          }
        }

        storage = {
          trace = {
            backend = "local"
            local   = { path = "/var/tempo/traces" }
            wal     = { path = "/var/tempo/wal" }
          }
        }

        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "500m", memory = "1Gi" }
        }
      }

      persistence = {
        enabled = true
        size    = "10Gi"
      }

      serviceMonitor = {
        enabled         = true
        additionalLabels = { release = "prometheus-stack" }
      }
    })
  ]

  timeout = 300
  wait    = true

  depends_on = [
    kubernetes_namespace_v1.monitoring,
    helm_release.prometheus_stack
  ]
}


# 4. OpenTelemetry Collector
#    Recebe, processa e roteia métricas
#    logs e traces para Prometheus, Loki e Tempo
resource "helm_release" "otel_collector" {
  name       = "otel-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.otel_chart_version != "" ? var.otel_chart_version : null
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    yamlencode({
      # DaemonSet: um pod por nó para coleta local de métricas e logs
      mode = "daemonset"

      # Por padrão, o chart só cria um Service quando mode != daemonset.
      # Precisamos habilitar explicitamente para que as apps no namespace
      # 'toggle' tenham um endereço estável (Service ClusterIP) para enviar OTLP.
      service = {
        enabled = true
      }

      image = {
        repository = "otel/opentelemetry-collector-contrib"
        # tag        = "0.105.0"
      }

      ports = {
        otlp      = { enabled = true, containerPort = 4317, protocol = "TCP" }
        otlp-http = { enabled = true, containerPort = 4318, protocol = "TCP" }
        # metrics (8888) é gerenciado internamente pelo collector
        # metrics   = { enabled = true, containerPort = 8888, protocol = "TCP" }
      }

      # RBAC para leitura de recursos k8s (kubeletstats + k8sattributes)
      clusterRole = {
        create = true
        rules = [
          {
            apiGroups = [""]
            resources = ["nodes", "nodes/proxy", "nodes/metrics", "nodes/stats",
              "services", "endpoints", "pods", "namespaces"]
            verbs = ["get", "list", "watch"]
          },
          {
            apiGroups = ["apps"]
            resources = ["replicasets", "deployments", "daemonsets", "statefulsets"]
            verbs     = ["get", "list", "watch"]
          },
          {
            nonResourceURLs = ["/metrics", "/metrics/cadvisor"]
            verbs           = ["get"]
          }
        ]
      }

      # Volumes para leitura dos arquivos de log dos containers
      extraVolumes = [
        { name = "varlogpods", hostPath = { path = "/var/log/pods" } },
        { name = "varlibdockercontainers", hostPath = { path = "/var/lib/docker/containers" } }
      ]

      extraVolumeMounts = [
        { name = "varlogpods", mountPath = "/var/log/pods", readOnly = true },
        { name = "varlibdockercontainers", mountPath = "/var/lib/docker/containers", readOnly = true }
      ]

      # Variável de ambiente para identificar o nó atual
      extraEnvs = [{
        name      = "K8S_NODE_NAME"
        valueFrom = { fieldRef = { fieldPath = "spec.nodeName" } }
      }]

      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }

      serviceMonitor = { enabled = true, namespace = "monitoring" }

      # Pipeline do OTel Collector
      config = {
        receivers = {
          # Recebe telemetria OTLP das aplicações (métricas, logs, traces)
          otlp = {
            protocols = {
              grpc = { endpoint = "0.0.0.0:4317" }
              http = { endpoint = "0.0.0.0:4318" }
            }
          }

          # Coleta métricas de nó, pod e container via kubelet
          kubeletstats = {
            collection_interval  = "30s"
            auth_type            = "serviceAccount"
            endpoint             = "https://$${env:K8S_NODE_NAME}:10250"
            insecure_skip_verify = true
            metric_groups        = ["node", "pod", "container"]
          }

          # Lê arquivos de log de todos os containers do nó
          filelog = {
            include           = ["/var/log/pods/*/*/*.log"]
            exclude           = ["/var/log/pods/*/otel-collector*/*.log"]
            include_file_path = true
            include_file_name = false
            operators = [
              {
                type   = "router", id = "get-format"
                routes = [
                  { output = "parser-docker", expr = "body matches \"^\\\\{\"" },
                  { output = "parser-containerd", expr = "body matches \"^[^ Z]+Z\"" }
                ]
              },
              { type = "json_parser", id = "parser-docker", output = "extract-k8s-info" },
              {
                type      = "regex_parser"
                id        = "parser-containerd"
                regex     = "^(?P<time>[^ ^Z]+Z) (?P<stream>stdout|stderr) (?P<logtag>[^ ]*) ?(?P<log>.*)$"
                output    = "extract-k8s-info"
                timestamp = { parse_from = "attributes.time", layout = "%Y-%m-%dT%H:%M:%S.%LZ" }
              },
              # Extrai namespace/pod/container do caminho do arquivo de log
              {
                type       = "regex_parser"
                id         = "extract-k8s-info"
                regex      = "^.*/(?P<namespace>[^_]+)_(?P<pod_name>[^_]+)_(?P<uid>[a-f0-9-]+)/(?P<container_name>[^/]+)/[0-9]*.log$"
                parse_from = "attributes[\"log.file.path\"]"
              },
              { type = "move", from = "attributes.namespace",      to = "resource[\"k8s.namespace.name\"]" },
              { type = "move", from = "attributes.pod_name",       to = "resource[\"k8s.pod.name\"]" },
              { type = "move", from = "attributes.container_name", to = "resource[\"k8s.container.name\"]" },
              { type = "move", from = "attributes.uid",            to = "resource[\"k8s.pod.uid\"]" }
            ]
          }
        }

        processors = {
          # Enriquece spans/métricas/logs com atributos k8s (via API do cluster)
          k8sattributes = {
            auth_type   = "serviceAccount"
            passthrough = false
            extract = {
              metadata = ["k8s.pod.name", "k8s.pod.uid", "k8s.deployment.name",
                "k8s.namespace.name", "k8s.node.name", "k8s.pod.start_time"]
              labels = [
                { tag_name = "app", key = "app", from = "pod" },
                { tag_name = "app.kubernetes.io/name", key = "app.kubernetes.io/name", from = "pod" }
              ]
            }
          }

          # Adiciona o nome do cluster EKS como atributo de recurso
          resource = {
            attributes = [{
              key    = "k8s.cluster.name"
              value  = "${var.name_prefix}-eks-cluster"
              action = "upsert"
            }]
          }
          batch          = { send_batch_size = 1000, timeout = "10s" }
          memory_limiter = { check_interval = "1s", limit_percentage = 75, spike_limit_percentage = 20 }
        }

        exporters = {
          # Envia métricas ao Prometheus via remote_write
          prometheusremotewrite = {
            endpoint = "http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090/api/v1/write"
            tls      = { insecure = true }
            resource_to_telemetry_conversion = { enabled = true }
          }

          # Envia logs ao Loki via OTLP HTTP nativo
          "otlphttp/loki" = {
            endpoint = "http://loki-gateway.monitoring.svc.cluster.local/otlp"
            tls      = { insecure = true }
          }

          # Envia traces ao Tempo via OTLP gRPC nativo
          "otlp/tempo" = {
            endpoint = "tempo.monitoring.svc.cluster.local:4317"
            tls      = { insecure = true }
          }

          # Debug - reduzir ou remover em produção
          debug = { verbosity = "normal", sampling_initial = 5, sampling_thereafter = 200 }
        }

        extensions = {
          health_check = { endpoint = "0.0.0.0:13133" }
          pprof        = {}
          zpages       = {}
        }

        service = {
          extensions = ["health_check", "pprof", "zpages"]
          pipelines = {
            # Métricas: kubelet + OTLP das apps - Prometheus
            metrics = {
              receivers  = ["otlp", "kubeletstats"]
              processors = ["memory_limiter", "k8sattributes", "resource", "batch"]
              exporters  = ["prometheusremotewrite"]
            }
            # Logs: arquivos dos containers + OTLP das apps - Loki
            logs = {
              receivers  = ["otlp", "filelog"]
              processors = ["memory_limiter", "k8sattributes", "resource", "batch"]
              exporters  = ["otlphttp/loki"]
            }
            # Traces: OTLP dos apps - Tempo
            traces = {
              receivers  = ["otlp"]
              processors = ["memory_limiter", "k8sattributes", "resource", "batch"]
              exporters  = ["otlp/tempo", "debug"]
            }
          }
        }
      }

      livenessProbe  = { httpGet = { path = "/", port = 13133 } }
      readinessProbe = { httpGet = { path = "/", port = 13133 } }
    })
  ]

  timeout = 300
  wait    = true

  # OTel deve subir depois de Prometheus, Loki e Tempo (endpoints já disponíveis)
  depends_on = [
    helm_release.prometheus_stack,
    helm_release.loki,
    helm_release.tempo
  ]
}