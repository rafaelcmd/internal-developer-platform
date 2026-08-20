# Task fixtures

One file per message shape the scaffold state machine puts on the task queue for
a `.waitForTaskToken` task. `make seed E=events/reserve-name.json` enqueues one
against the LocalStack queue that `docker compose` creates.

`TaskToken` is a placeholder. Everything up to the callback runs for real —
deserialization, dispatch, the use case, the DynamoDB write — and then
`SendTaskSuccess` is rejected because no execution is waiting on that token, so
the message is left on the queue and redelivered. That is the designed behaviour
(see the deletion rule in `TaskQueueWorker`), not a bug: exercising the callback
end to end needs a real execution, which is the integration test's job.
