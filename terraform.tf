provider "aws" {
  region = "eu-central-1"
}

data "aws_iam_policy" "LambdaExecute" {
  arn = "arn:aws:iam::aws:policy/AWSLambdaExecute"
}

variable "account_id" {}

data "aws_caller_identity" "current" {}

#----------------------ZIP-Files----------------------------
data "archive_file" "validatorzip" {
  type = "zip"
  source_dir = ".aws-sam/build/ValidatorFunction"
  output_path = "ValidatorFunction.zip"
}

data "archive_file" "calculatorzip" {
  type = "zip"
  source_dir = ".aws-sam/build/CalculatorFunction"
  output_path = "CalculatorFunction.zip"
}
#-----------------------------------------------------------
#------------------------ValidatorLambda-----------------------------
data "aws_iam_policy_document" "ValidatorPolicy" {
  statement {
    sid = ""
    effect = "Allow"

    principals {
      identifiers = [
        "lambda.amazonaws.com"]
      type = "Service"
    }

    actions = [
      "sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam_validatorRole" {
  name = "iam_for_validatorLambda"
  assume_role_policy = "${data.aws_iam_policy_document.ValidatorPolicy.json}"
}

resource "aws_iam_policy" "validatorRole_DynamoDB" {
  name = "validatorRole_DynamoDB"
  path = "/"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:Query",
        "dynamodb:GetItem"
      ],
      "Resource": "${aws_dynamodb_table.dynamodb.arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "validator_dynamoDB_attachment" {
  policy_arn = aws_iam_policy.validatorRole_DynamoDB.arn
  role = aws_iam_role.iam_validatorRole.name
}

resource "aws_iam_policy" "validatorRole_SQS" {
  name = "validatorRole_SQS"
  path = "/"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage"
      ],
      "Resource": "${aws_sqs_queue.sqs.arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "validator_sqs_attachment" {
  policy_arn = aws_iam_policy.validatorRole_SQS.arn
  role = aws_iam_role.iam_validatorRole.name
}

resource "aws_iam_role_policy_attachment" "validator_lambdaExecute_attachment" {
  policy_arn = data.aws_iam_policy.LambdaExecute.arn
  role = aws_iam_role.iam_validatorRole.name
}


resource "aws_lambda_permission" "invokeValidatorLambda" {
  statement_id = "AllowAPIGatewayInvoke"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.validatorlambda.arn
  principal = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_deployment.deployment.execution_arn}/${aws_api_gateway_method.method.http_method}${aws_api_gateway_resource.proxy.path}"
}

resource "aws_lambda_function" "validatorlambda" {
  function_name = "ValidatorLambda"

  filename = "${data.archive_file.validatorzip.output_path}"
  source_code_hash = "${data.archive_file.validatorzip.output_base64sha256}"

  role = "${aws_iam_role.iam_validatorRole.arn}"
  handler = "app.lambda_handler"
  runtime = "python3.7"

  environment {
    variables = {
      sqs = aws_sqs_queue.sqs.id
      dynamodbtable = aws_dynamodb_table.dynamodb.name
    }
  }
}

#--------------------------------------------------------------------------
#------------------------CalculateLambda-----------------------------------
data "aws_iam_policy_document" "CalculatePolicy" {
  statement {
    sid = ""
    effect = "Allow"

    principals {
      identifiers = [
        "lambda.amazonaws.com"]
      type = "Service"
    }

    actions = [
      "sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam_calculateRole" {
  name = "iam_for_calculateLambda"
  assume_role_policy = "${data.aws_iam_policy_document.CalculatePolicy.json}"
}

resource "aws_iam_policy" "calculateRole_DynamoDB" {
  name = "calculateRole_DynamoDB"
  path = "/"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem"
      ],
      "Resource": "${aws_dynamodb_table.dynamodb.arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "calculate_dynamoDB_attachment" {
  policy_arn = aws_iam_policy.calculateRole_DynamoDB.arn
  role = aws_iam_role.iam_calculateRole.name
}

resource "aws_iam_policy" "calculateRole_SQS" {
  name = "calculateRole_SQS"
  path = "/"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "${aws_sqs_queue.sqs.arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "calculate_sqs_attachment" {
  policy_arn = aws_iam_policy.calculateRole_SQS.arn
  role = aws_iam_role.iam_calculateRole.name
}

resource "aws_iam_role_policy_attachment" "calculate_lambdaExecute_attachment" {
  policy_arn = data.aws_iam_policy.LambdaExecute.arn
  role = aws_iam_role.iam_calculateRole.name
}

resource "aws_lambda_event_source_mapping" "calculate_sqs_trigger" {
  event_source_arn = aws_sqs_queue.sqs.arn
  function_name = aws_lambda_function.calculatelambda.arn
}

resource "aws_lambda_function" "calculatelambda" {
  function_name = "CalculateLambda"

  filename = "${data.archive_file.calculatorzip.output_path}"
  source_code_hash = "${data.archive_file.calculatorzip.output_base64sha256}"

  role = "${aws_iam_role.iam_calculateRole.arn}"
  handler = "app.lambda_handler"
  runtime = "python3.7"

  timeout = 30


  environment {
    variables = {
      dynamodbtable = aws_dynamodb_table.dynamodb.name
    }
  }
}

#--------------------------------------------------------------------------
#---------------------------------DynamoDB---------------------------------

resource "aws_dynamodb_table" "dynamodb" {
  hash_key = "number"
  name = "factorialNumber"
  attribute {
    name = "number"
    type = "N"
  }
  billing_mode = "PAY_PER_REQUEST"
}
#--------------------------------------------------------------------------
#-----------------------------------SQS------------------------------------
resource "aws_sqs_queue" "sqs" {
  name = "factorialSQS"
  message_retention_seconds = 120
}

resource "aws_sqs_queue_policy" "sqs_queue_policy" {
  queue_url = aws_sqs_queue.sqs.id
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Sid": "First",
      "Effect": "Allow",
      "Principal": {
          "AWS": [
              "${data.aws_caller_identity.current.account_id}"
          ]
      },
      "Action": ["sqs:SendMessage"],
      "Resource": "${aws_sqs_queue.sqs.arn}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "${aws_lambda_function.validatorlambda.arn}}"
        }
      }
    },
    {
      "Sid": "Second",
      "Effect": "Allow",
      "Principal": {
          "AWS": [
              "${data.aws_caller_identity.current.account_id}"
          ]
      },
      "Action": ["sqs:ReceiveMessage",
                 "sqs:DeleteMessage"],
      "Resource": "${aws_sqs_queue.sqs.arn}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "${aws_lambda_function.calculatelambda.arn}}"
        }
      }
    }
  ]
}
POLICY
}
#--------------------------------------------------------------------------
#-----------------------------API Gateway----------------------------------
resource "aws_api_gateway_rest_api" "api_gateway" {
  name = "FactorialAPI"
  description = "API for factorial calculation"
}

resource "aws_api_gateway_resource" "proxy" {
  parent_id = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part = "factorial"
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
}

resource "aws_api_gateway_method" "method" {
  authorization = "NONE"
  http_method = "POST"
  resource_id = aws_api_gateway_resource.proxy.id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
}

resource "aws_api_gateway_integration" "integration_lambda" {
  http_method = aws_api_gateway_method.method.http_method
  resource_id = aws_api_gateway_method.method.resource_id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  type = "AWS_PROXY"
  integration_http_method = "POST"
  uri = aws_lambda_function.validatorlambda.invoke_arn
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.integration_lambda,
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name = "Test"
}
#--------------------------------------------------------------------------