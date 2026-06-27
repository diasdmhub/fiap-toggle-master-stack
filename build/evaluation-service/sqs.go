package main

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/sqs"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/propagation"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

// Evento que será enviado para a fila
type EvaluationEvent struct {
	UserID    string    `json:"user_id"`
	FlagName  string    `json:"flag_name"`
	Result    bool      `json:"result"`
	Timestamp time.Time `json:"timestamp"`
}

// sqsCarrier adapta um mapa de MessageAttributes para a interface TextMapCarrier
// do OpenTelemetry, permitindo injetar o traceparent como atributo da mensagem.
type sqsCarrier map[string]*sqs.MessageAttributeValue

func (c sqsCarrier) Get(key string) string {
	if v, ok := c[key]; ok && v.StringValue != nil {
		return *v.StringValue
	}
	return ""
}
func (c sqsCarrier) Set(key, value string) {
	c[key] = &sqs.MessageAttributeValue{
		DataType:    aws.String("String"),
		StringValue: aws.String(value),
	}
}
func (c sqsCarrier) Keys() []string {
	keys := make([]string, 0, len(c))
	for k := range c {
		keys = append(keys, k)
	}
	return keys
}

// sendEvaluationEvent envia um evento para a fila SQS com o trace context propagado
// como message attributes (traceparent / tracestate), permitindo que o
// analytics-service continue o mesmo trace ao consumir a mensagem.
func (a *App) sendEvaluationEvent(ctx context.Context, userID, flagName string, result bool) {
	// Se a URL da fila não foi configurada, apenas loga localmente e sai.
	if a.SqsSvc == nil || a.SqsQueueURL == "" {
		log.Printf("[SQS_DISABLED] Evento: User '%s', Flag '%s', Result '%t'", userID, flagName, result)
		return
	}

	// Cria um span filho para representar a operação de publish no SQS
	ctx, span := tracer.Start(ctx, "SQS SendMessage",
		trace.WithSpanKind(trace.SpanKindProducer),
		trace.WithAttributes(
			semconv.MessagingSystemAWSSqs,
			semconv.MessagingDestinationName(a.SqsQueueURL),
			semconv.MessagingOperationTypePublish,
		),
	)
	defer span.End()

	event := EvaluationEvent{
		UserID:    userID,
		FlagName:  flagName,
		Result:    result,
		Timestamp: time.Now().UTC(),
	}

	body, err := json.Marshal(event)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		log.Printf("Erro ao serializar evento SQS: %v", err)
		return
	}

	// Injeta traceparent + tracestate nos MessageAttributes da mensagem SQS
	carrier := sqsCarrier{}
	propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	).Inject(ctx, carrier)

	_, err = a.SqsSvc.SendMessage(&sqs.SendMessageInput{
		MessageBody:       aws.String(string(body)),
		QueueUrl:          aws.String(a.SqsQueueURL),
		MessageAttributes: carrier,
	})

	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		log.Printf("Erro ao enviar mensagem para SQS: %v", err)
	} else {
		log.Printf("Evento de avaliação enviado para SQS (Flag: %s)", flagName)
	}
}