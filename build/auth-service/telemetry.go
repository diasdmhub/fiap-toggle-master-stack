package main

import (
	"context"
	"log"
	"os"
	"strings"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/metric"
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

// setupOTel inicializa o SDK do OpenTelemetry: configura TracerProvider e
// MeterProvider com exportadores OTLP/gRPC compartilhando a mesma conexão.
// O MeterProvider é necessário para que o otelhttp emita a métrica
// http.server.duration automaticamente em cada requisição.
// Retorna uma função de shutdown que faz flush e fecha ambos os providers.
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

	// --- Resource (atributos comuns a traces e métricas) ---
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
			semconv.ServiceNamespace("toggle"),
		),
		resource.WithFromEnv(),
		resource.WithHost(),
		resource.WithContainer(),
	)
	if err != nil {
		return nil, err
	}

	// --- TracerProvider ---
	traceExporter, err := otlptracegrpc.New(ctx, otlptracegrpc.WithGRPCConn(conn))
	if err != nil {
		return nil, err
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)

	// --- MeterProvider ---
	// Sem o MeterProvider registrado globalmente, o otelhttp não emite a
	// métrica http.server.duration — os handlers são instrumentados mas as
	// medições são descartadas silenciosamente.
	metricExporter, err := otlpmetricgrpc.New(ctx, otlpmetricgrpc.WithGRPCConn(conn))
	if err != nil {
		return nil, err
	}
	mp := metric.NewMeterProvider(
		metric.WithReader(metric.NewPeriodicReader(metricExporter)),
		metric.WithResource(res),
	)
	otel.SetMeterProvider(mp)

	// --- Propagador W3C (traceparent / tracestate) ---
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	log.Printf("OpenTelemetry inicializado (service=%s, endpoint=%s)", serviceName, endpoint)

	// Shutdown encadeia flush do MeterProvider e do TracerProvider
	return func(ctx context.Context) error {
		if err := mp.Shutdown(ctx); err != nil {
			log.Printf("Erro ao encerrar MeterProvider: %v", err)
		}
		return tp.Shutdown(ctx)
	}, nil
}