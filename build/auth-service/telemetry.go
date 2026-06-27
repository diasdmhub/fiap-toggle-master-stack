package main

import (
	"context"
	"log"
	"os"
	"strings"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// defaultOTLPEndpoint aponta para o Service do OTel Collector (DaemonSet)
// dentro do cluster, namespace "monitoring".
const defaultOTLPEndpoint = "otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4317"

// tracer é usado para criar spans manuais fora do que o otelhttp já instrumenta automaticamente.
var tracer = otel.Tracer("auth-service")

// setupOTel inicializa o SDK de tracing do OpenTelemetry: cria o exportador
// OTLP/gRPC para o OTel Collector, registra o TracerProvider e o propagador
// W3C Trace Context globais. Retorna uma função de shutdown (flush + close).
func setupOTel(ctx context.Context, serviceName string) (func(context.Context) error, error) {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = defaultOTLPEndpoint
	}
	// grpc.NewClient espera "host:port", sem o esquema da URL (http://, https://)
	endpoint = strings.TrimPrefix(strings.TrimPrefix(endpoint, "https://"), "http://")

	conn, err := grpc.NewClient(endpoint, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, err
	}

	exporter, err := otlptracegrpc.New(ctx, otlptracegrpc.WithGRPCConn(conn))
	if err != nil {
		return nil, err
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
			semconv.ServiceNamespace("toggle"),
		),
		resource.WithFromEnv(), // permite OTEL_RESOURCE_ATTRIBUTES extras
		resource.WithHost(),
		resource.WithContainer(),
	)
	if err != nil {
		return nil, err
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{}, // traceparent / tracestate (W3C)
		propagation.Baggage{},
	))

	log.Printf("OpenTelemetry inicializado (service=%s, endpoint=%s)", serviceName, endpoint)
	return tp.Shutdown, nil
}