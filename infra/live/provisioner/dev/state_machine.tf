# The scaffold state machine: one execution turns one accepted provision request
# into a repository and the cloud resources that go with it. Every worker step is
# a callback, so workflow state lives here rather than in whichever pod picked
# the message up. The queues it sends to belong to the scaffolder, which
# publishes their names to SSM. See docs/adr/0006 for why it is owned here.

locals {
  state_machine_name = "${var.project}-scaffold-${var.environment}"

  # The send is the only part of a callback task that is safe to retry here.
  #
  # A failed send means the task never reached a worker, so repeating it repeats
  # nothing. Everything past that point already has a retry loop: SQS redelivers
  # the message under the same token until the worker reports an outcome or the
  # redrive limit moves it to the dead-letter queue.
  #
  # Retrying States.Timeout would add a second message with a fresh token while
  # the first is still on the queue, so the same task runs twice and the
  # abandoned copy dead-letters on a token Step Functions no longer holds. A
  # timeout is a failure to report, and a second copy cannot report either.
  #
  # Domain failures reported through SendTaskFailure are absent for a simpler
  # reason: a name held by another request does not come free by asking again.
  task_retry = [
    {
      ErrorEquals     = ["SQS.SdkClientException", "SQS.AmazonSQSException"]
      IntervalSeconds = 2
      MaxAttempts     = 4
      BackoffRate     = 2
      JitterStrategy  = "FULL"
    },
  ]

  # UpdateItem with a fixed SET expression produces the same item however many
  # times it runs, so every fault worth distinguishing here is transient.
  record_state_retry = [
    {
      ErrorEquals = [
        "DynamoDB.ThrottlingException",
        "DynamoDB.ProvisionedThroughputExceededException",
        "DynamoDB.RequestLimitExceeded",
        "DynamoDB.InternalServerError",
        "DynamoDB.SdkClientException",
        "States.Timeout",
      ]
      IntervalSeconds = 1
      MaxAttempts     = 4
      BackoffRate     = 2
      JitterStrategy  = "FULL"
    },
  ]

  request_state_key = {
    PK = { "S.$" = "States.Format('REQUEST#{}', $.request_id)" }
    SK = { S = "STATE" }
  }

  # Two states that differ by one field. The Amazon States Language has no
  # optional-field access: a "$." path that does not resolve fails the state
  # with States.Runtime, which no Retry clears, and description is the one field
  # a developer may omit. Generating both from one definition keeps the pair
  # from drifting.
  create_repository_states = {
    for state_name, extra_input in {
      CreateRepositoryWithDescription = { "Description.$" = "$.application.description" }
      CreateRepository                = {}
      } : state_name => {
      Type     = "Task"
      Comment  = "Creates the GitHub repository. Served by the github worker, the only one holding the App private key."
      Resource = "arn:aws:states:::sqs:sendMessage.waitForTaskToken"

      Parameters = {
        QueueUrl = data.aws_sqs_queue.scaffolder_github_tasks.url
        MessageBody = {
          Task          = "CreateRepository"
          "TaskToken.$" = "$$.Task.Token"
          Input = merge({
            "ApplicationName.$" = "$.application.name"
            "RequestId.$"       = "$.request_id"
            "Template.$"        = "$.application.template"
          }, extra_input)
        }
      }

      ResultPath     = "$.repository"
      TimeoutSeconds = var.create_repository_timeout_seconds
      Retry          = local.task_retry
      End            = true
    }
  }

  # Provisioning the requested resources runs beside repository creation: the
  # repository does not need the infrastructure to exist, and serializing them
  # would make a developer wait out a Terraform run before seeing their
  # repository. What the repository contains is a separate question, answered by
  # a join state after this Parallel rather than by ordering the two branches.
  # See docs/adr/0007.
  #
  # Until the infra worker exists there is no queue to send to, and a request
  # naming resources fails here rather than reporting success for a database
  # nothing created. Setting infra_worker_task_queue_name replaces the Fail
  # state with the callback task.
  #
  # The two states are encoded and decoded around the conditional because the
  # arms of a Terraform conditional must share one type, and a Fail state and a
  # Task state do not.
  provision_infra_state = jsondecode(
    var.infra_worker_task_queue_name == null
    ? jsonencode({
      Type    = "Fail"
      Comment = "No infra worker is deployed. Set infra_worker_task_queue_name to turn this into a callback task."
      Error   = "INFRA_WORKER_UNAVAILABLE"
      Cause   = "This request asked for cloud resources and no infra worker is deployed to provision them."
    })
    : jsonencode({
      Type     = "Task"
      Comment  = "Executes infrastructure-as-code for the requested resources."
      Resource = "arn:aws:states:::sqs:sendMessage.waitForTaskToken"

      Parameters = {
        QueueUrl = one(data.aws_sqs_queue.infra_worker_tasks[*].url)
        MessageBody = {
          Task          = "ProvisionInfra"
          "TaskToken.$" = "$$.Task.Token"
          Input = {
            "ApplicationName.$" = "$.application.name"
            "RequestId.$"       = "$.request_id"
            "Resources.$"       = "$.resources"
          }
        }
      }

      ResultPath     = "$.infrastructure"
      TimeoutSeconds = var.provision_infra_timeout_seconds
      Retry          = local.task_retry
      End            = true
    })
  )

  definition = {
    Comment = join(" ", [
      "Turns one accepted provision request into a repository and its cloud resources.",
      "Every worker state is a .waitForTaskToken callback: the worker holds no connection open and the workflow holds the state.",
    ])

    StartAt = "RecordRequestAccepted"

    # The ceiling on a whole request. Above the sum of the task timeouts, so a
    # task that is merely slow is stopped by its own timeout and reported, not
    # by this one.
    TimeoutSeconds = var.execution_timeout_seconds

    States = {
      RecordRequestAccepted = {
        Type = "Task"
        Comment = join(" ", [
          "Writes the request row before any side effect happens.",
          "An execution that dies after this point still leaves a record naming what it was in the middle of.",
        ])
        Resource = "arn:aws:states:::dynamodb:updateItem"

        Parameters = {
          TableName                = module.requests.table_name
          Key                      = local.request_state_key
          UpdateExpression         = "SET #status = :status, ExecutionArn = :executionArn, ApplicationName = :applicationName, Template = :template, RequestedBy = :requestedBy, StartedAt = :startedAt, UpdatedAt = :updatedAt"
          ExpressionAttributeNames = { "#status" = "Status" }
          ExpressionAttributeValues = {
            ":status"          = { S = "RUNNING" }
            ":executionArn"    = { "S.$" = "$$.Execution.Id" }
            ":applicationName" = { "S.$" = "$.application.name" }
            ":template"        = { "S.$" = "$.application.template" }
            ":requestedBy"     = { "S.$" = "$.requested_by" }
            ":startedAt"       = { "S.$" = "$$.Execution.StartTime" }
            ":updatedAt"       = { "S.$" = "$$.State.EnteredTime" }
          }
        }

        # Null discards the UpdateItem response so the next state sees the
        # request as the provisioner sent it.
        ResultPath     = null
        TimeoutSeconds = var.record_state_timeout_seconds
        Retry          = local.record_state_retry
        Catch          = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "RecordRequestFailed" }]
        Next           = "ReserveName"
      }

      ReserveName = {
        Type = "Task"
        Comment = join(" ", [
          "Claims the application name for this request, ahead of both branches.",
          "Two requests for one name have to collide before either creates anything.",
        ])
        Resource = "arn:aws:states:::sqs:sendMessage.waitForTaskToken"

        Parameters = {
          QueueUrl = data.aws_sqs_queue.scaffolder_state_tasks.url
          MessageBody = {
            Task          = "ReserveName"
            "TaskToken.$" = "$$.Task.Token"
            Input = {
              "ApplicationName.$" = "$.application.name"
              "RequestId.$"       = "$.request_id"
            }
          }
        }

        ResultPath     = "$.reservation"
        TimeoutSeconds = var.reserve_name_timeout_seconds
        Retry          = local.task_retry
        Catch          = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "RecordRequestFailed" }]
        Next           = "ScaffoldAndProvision"
      }

      ScaffoldAndProvision = {
        Type    = "Parallel"
        Comment = "The repository and the infrastructure are independent. Both branches receive the whole request."

        Branches = [
          {
            StartAt = "HasDescription"
            States = merge(
              {
                HasDescription = {
                  Type    = "Choice"
                  Comment = "Routes around the optional description field. See create_repository_states in state_machine.tf."
                  Choices = [
                    {
                      Variable  = "$.application.description"
                      IsPresent = true
                      Next      = "CreateRepositoryWithDescription"
                    },
                  ]
                  Default = "CreateRepository"
                }
              },
              local.create_repository_states,
            )
          },
          {
            StartAt = "HasResources"
            States = {
              HasResources = {
                Type = "Choice"
                Choices = [
                  {
                    Variable  = "$.resources[0]"
                    IsPresent = true
                    Next      = "ProvisionInfra"
                  },
                ]
                Default = "NoInfrastructureRequested"
              }

              NoInfrastructureRequested = {
                Type       = "Pass"
                Comment    = "An application with no cloud resources is a supported golden path, not an empty branch to run anyway."
                Result     = { Provisioned = false }
                ResultPath = "$.infrastructure"
                End        = true
              }

              ProvisionInfra = local.provision_infra_state
            }
          },
        ]

        # Each branch returns the request it received plus what it added, so the
        # repository result is at $.results[0].repository.
        ResultPath = "$.results"
        Catch      = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "RecordRequestFailed" }]
        Next       = "RecordRequestSucceeded"
      }

      RecordRequestSucceeded = {
        Type     = "Task"
        Comment  = "The terminal record a caller polls for. Written before the Succeed state, so a request is never reported complete without one."
        Resource = "arn:aws:states:::dynamodb:updateItem"

        Parameters = {
          TableName                = module.requests.table_name
          Key                      = local.request_state_key
          UpdateExpression         = "SET #status = :status, RepositoryFullName = :repositoryFullName, RepositoryUrl = :repositoryUrl, CompletedAt = :completedAt, UpdatedAt = :updatedAt"
          ExpressionAttributeNames = { "#status" = "Status" }
          ExpressionAttributeValues = {
            ":status"             = { S = "SUCCEEDED" }
            ":repositoryFullName" = { "S.$" = "$.results[0].repository.FullName" }
            ":repositoryUrl"      = { "S.$" = "$.results[0].repository.HtmlUrl" }
            ":completedAt"        = { "S.$" = "$$.State.EnteredTime" }
            ":updatedAt"          = { "S.$" = "$$.State.EnteredTime" }
          }
        }

        ResultPath     = null
        TimeoutSeconds = var.record_state_timeout_seconds
        Retry          = local.record_state_retry

        # Straight to the failure state rather than through RecordRequestFailed,
        # which would be a second write to the table that just refused one. The
        # row stays RUNNING and the execution ends failed, which is the accurate
        # pair: the work succeeded and the platform cannot confirm it.
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "RequestFailed" }]
        Next  = "RequestSucceeded"
      }

      RequestSucceeded = {
        Type = "Succeed"
      }

      RecordRequestFailed = {
        Type     = "Task"
        Comment  = "Terminal record for every failure path. Reached by catch from each state that can fail."
        Resource = "arn:aws:states:::dynamodb:updateItem"

        Parameters = {
          TableName                = module.requests.table_name
          Key                      = local.request_state_key
          UpdateExpression         = "SET #status = :status, ErrorName = :errorName, ErrorDetail = :errorDetail, CompletedAt = :completedAt, UpdatedAt = :updatedAt"
          ExpressionAttributeNames = { "#status" = "Status" }
          ExpressionAttributeValues = {
            ":status"    = { S = "FAILED" }
            ":errorName" = { "S.$" = "$.error.Error" }
            # The catcher output as one string. Cause is absent for some service
            # errors, and a "$." path to a missing field is itself a failure.
            ":errorDetail" = { "S.$" = "States.JsonToString($.error)" }
            ":completedAt" = { "S.$" = "$$.State.EnteredTime" }
            ":updatedAt"   = { "S.$" = "$$.State.EnteredTime" }
          }
        }

        ResultPath     = null
        TimeoutSeconds = var.record_state_timeout_seconds
        Retry          = local.record_state_retry

        # Null keeps $.error as the failure that got the execution here, so the
        # Fail state reports the scaffold error rather than the write that could
        # not record it.
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = null, Next = "RequestFailed" }]
        Next  = "RequestFailed"
      }

      RequestFailed = {
        Type      = "Fail"
        ErrorPath = "$.error.Error"
        CausePath = "States.JsonToString($.error)"
      }
    }
  }
}

# What the machine is allowed to do, which is exactly what its states call:
# put a task on a worker's queue, and write the request row. It runs no
# compute of its own and reads no other service's data.
data "aws_iam_policy_document" "state_machine" {
  statement {
    sid     = "SendScaffolderTasks"
    actions = ["sqs:SendMessage"]
    resources = concat(
      [
        data.aws_sqs_queue.scaffolder_state_tasks.arn,
        data.aws_sqs_queue.scaffolder_github_tasks.arn,
      ],
      data.aws_sqs_queue.infra_worker_tasks[*].arn,
    )
  }

  statement {
    sid       = "WriteRequestState"
    actions   = ["dynamodb:UpdateItem"]
    resources = [module.requests.table_arn]
  }
}

module "state_machine" {
  source = "../../../modules/aws/step_functions"

  name             = local.state_machine_name
  role_description = "Scaffold state machine: sends callback tasks to the scaffolder queues and records request state"

  # STANDARD, not EXPRESS. Express executions cap at five minutes, do not
  # support .waitForTaskToken, and keep no durable history, all three of which
  # this workflow depends on.
  type       = "STANDARD"
  definition = jsonencode(local.definition)

  policy_json = data.aws_iam_policy_document.state_machine.json

  log_level             = var.state_machine_log_level
  log_retention_in_days = var.state_machine_log_retention_in_days
  tracing_enabled       = var.state_machine_tracing_enabled

  alarm_actions = [data.aws_ssm_parameter.observability_alerts_topic_arn.value]

  tags = local.tags
}

# Published for the provisioner pod, which resolves both at startup rather than
# carrying an account id in a committed manifest.

resource "aws_ssm_parameter" "state_machine_arn" {
  name  = "/idp/${var.service_name}/${var.environment}/scaffold_state_machine_arn"
  type  = "String"
  value = module.state_machine.state_machine_arn
  tags  = local.tags
}

resource "aws_ssm_parameter" "requests_table_name" {
  name  = "/idp/${var.service_name}/${var.environment}/requests_table_name"
  type  = "String"
  value = module.requests.table_name
  tags  = local.tags
}
