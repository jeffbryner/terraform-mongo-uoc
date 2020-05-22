terraform {
  required_version = ">=0.12.25"
  required_providers {
    aws = ">= 2.25.0"
  }
}

provider "aws" {
  region                  = "us-west-2"
  profile                 = "default"
}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

output "account_id" {
  value = "${data.aws_caller_identity.current.account_id}"
}

output "caller_arn" {
  value = "${data.aws_caller_identity.current.arn}"
}

output "caller_user" {
  value = "${data.aws_caller_identity.current.user_id}"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  owners = ["099720109477"] # Canonical
}
data "aws_ami" "amazon-linux-2-ami" {
  most_recent = true
  owners = ["amazon"]
  filter {
  name   = "owner-alias"
  values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_s3_bucket" "uoc_input_bucket" {
  bucket = "uoc-${data.aws_caller_identity.current.account_id}-input-bucket"
  acl    = "private"

  versioning {
    enabled = false
  }

  lifecycle_rule {
    enabled = true

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_public_access_block" "uoc_input_bucket" {
  bucket = aws_s3_bucket.uoc_input_bucket.id

  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "uoc_output_bucket" {
  bucket = "uoc-${data.aws_caller_identity.current.account_id}-output-bucket"
  acl    = "private"

  versioning {
    enabled = false
  }

  lifecycle_rule {
    enabled = true

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 360
    }
  }
}

resource "aws_s3_bucket_public_access_block" "uoc_output_bucket" {
  bucket = aws_s3_bucket.uoc_output_bucket.id

  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "uoc-firehose-role" {
  name = "uoc-firehose-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "uoc-firehose-policy" {
  name = "uoc-firehose-policy"
  role = aws_iam_role.uoc-firehose-role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": [
        "glue:GetTable",
        "glue:GetTableVersion",
        "glue:GetTableVersions"
      ],
      "Resource": "*"
    },
    {
      "Action": [
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.uoc_output_bucket.arn}",
        "${aws_s3_bucket.uoc_output_bucket.arn}/*"
      ]
    },
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": [
          "logs:PutLogEvents"
      ],
      "Resource": [
          "arn:aws:logs:us-west-2:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/uoc-firehose-logging:log-stream:*"
      ]
    },
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords"
      ],
      "Resource": "arn:aws:kinesis:us-west-2:${data.aws_caller_identity.current.account_id}:stream/uoc-firehose-logging"
    }
  ]
}
EOF
}

resource "aws_kinesis_firehose_delivery_stream" "uoc-firehose-logging" {
  name = "uoc-firehose-logging"
  destination = "extended_s3"
  extended_s3_configuration {
    bucket_arn = aws_s3_bucket.uoc_output_bucket.arn
    buffer_interval = 60
    buffer_size = 1
    compression_format = "GZIP"
    error_output_prefix = "errors"
    role_arn = aws_iam_role.uoc-firehose-role.arn
  }
}


resource "aws_s3_bucket" "uoc_athena_bucket" {
  bucket = "${data.aws_caller_identity.current.account_id}-aws-athena-query-results-${data.aws_region.current.name}"
  acl    = "private"

  versioning {
    enabled = false
  }

  lifecycle_rule {
    enabled = true

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_public_access_block" "uoc_athena_bucket" {
  bucket = aws_s3_bucket.uoc_athena_bucket.id

  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}

resource "aws_athena_database" "events" {
  name   = "events"
  bucket = aws_s3_bucket.uoc_athena_bucket.id
}

resource "aws_glue_catalog_table" "uoc_events_table" {
  name          = "events"
  database_name = aws_athena_database.events.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL = "TRUE"
  }

  partition_keys{
    name = "year"
    type = "string"
  }

  partition_keys{
    name = "month"
    type = "string"
  }

  partition_keys{
    name = "day"
    type = "string"
  }

  partition_keys{
    name = "hour"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.uoc_output_bucket.id}/"
    input_format = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.IgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json-serde"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "eventid"
      type = "string"
    }

    columns {
      name = "_base64"
      type = "string"
    }

    columns {
      name = "utctimestamp"
      type = "string"
    }

    columns {
      name = "severity"
      type = "string"
    }

    columns {
      name = "summary"
      type = "string"
    }

    columns {
      name = "category"
      type = "string"
    }

    columns {
      name = "source"
      type = "string"
    }

    columns {
      name = "tags"
      type = "array<string>"
    }

    columns {
      name = "plugins"
      type = "array<string>"
    }

    columns {
      name = "details"
      type = "string"
    }

  }
}

resource "aws_vpc" "mongo_uoc" {
  cidr_block = "10.10.0.0/24"
  enable_dns_hostnames= "true"
}
resource "aws_internet_gateway" "mongo_uoc" {
  vpc_id = aws_vpc.mongo_uoc.id

  tags = {
    Name = "mongo_uoc"
  }
}

resource "aws_security_group" "mongo_uoc" {
  name        = "mongo_uoc"
  description = "Allow ssh and efs"
  vpc_id      = aws_vpc.mongo_uoc.id

  ingress {
    # ssh
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    # Please restrict your ingress to only necessary IPs and ports.
    # Opening to 0.0.0.0/0 can lead to security vulnerabilities.
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
   # efs
      from_port   = 2049
      to_port     = 2049
      protocol    = "tcp"
      self = true
    }
  ingress {
    # mongo
      from_port   = 0
      to_port     = 27017
      protocol    = "tcp"
      self = true
    }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mongo_uoc"
  }
}

resource "aws_subnet" "mongo_uoc" {
  vpc_id            = aws_vpc.mongo_uoc.id
  availability_zone = var.availability_zone
  cidr_block        = "10.10.0.0/24"
}

resource "aws_route_table" "mongo_uoc" {
  vpc_id = aws_vpc.mongo_uoc.id
  route {
  cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.mongo_uoc.id
}
  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name = "mongo_uoc"
  }
}

resource "aws_route_table_association" "mongo_uoc" {
  subnet_id = aws_subnet.mongo_uoc.id
  route_table_id = aws_route_table.mongo_uoc.id
}

resource "aws_efs_file_system" "mongo_fs" {
  creation_token = "uoc_mongo_fs"

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name = "mongo_uoc"
  }
}
resource "aws_efs_mount_target" "mongo_fs" {
  file_system_id = aws_efs_file_system.mongo_fs.id
  subnet_id      = aws_subnet.mongo_uoc.id
  security_groups = [aws_security_group.mongo_uoc.id]
}
resource "aws_iam_role" "uoc_instance_role" {
  name = "uoc_instance_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "uoc_instance_profile" {
  name = "uoc_instance_profile"
  role = aws_iam_role.uoc_instance_role.name
}

resource "aws_iam_role_policy" "uoc_instance_policy" {
  name = "uoc_instance_policy"
  role = aws_iam_role.uoc_instance_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": [
      "glue:GetDatabase*",
      "glue:GetTable*",
      "glue:GetPartitions",
      "glue:BatchCreatePartition"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": [
      "athena:Get*",
      "athena:ListQueryExecutions",
      "athena:StartQueryExecution"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}
resource "aws_instance" "mongo_instance"{
  ami                    = data.aws_ami.amazon-linux-2-ami.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  monitoring             = false
  vpc_security_group_ids = [aws_security_group.mongo_uoc.id]
  subnet_id              = aws_subnet.mongo_uoc.id
  associate_public_ip_address = true
  iam_instance_profile = aws_iam_instance_profile.uoc_instance_profile.name


  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name = "mongo_uoc"
  }
  # ansible connection information
  connection {
    user        = var.aws_user
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }
  provisioner "file" {
    source      = "provision/wait-for-cloud-init.sh"
    destination = "/tmp/wait-for-cloud-init.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/wait-for-cloud-init.sh",
      "/tmp/wait-for-cloud-init.sh",
    ]
  }

  provisioner "ansible" {
    plays {
      playbook{
        file_path = "provision/playbook.yaml"
      }
      # https://docs.ansible.com/ansible/2.4/intro_inventory.html#hosts-and-groups
      groups = ["db-mongodb"]
      extra_vars = {
            efs_filesystem_address = aws_efs_file_system.mongo_fs.dns_name
      }
    }
    remote {
      skip_install = false
    }
  }
}

resource "aws_sagemaker_notebook_instance" "uoc-notebooks" {
    instance_type   = "ml.t2.medium"
    name            = "uoc-notebooks"
    role_arn        = "arn:aws:iam::717455710680:role/service-role/AmazonSageMaker-ExecutionRole-20200521T101682"
    security_groups = [aws_security_group.mongo_uoc.id]
    subnet_id       = aws_subnet.mongo_uoc.id
    tags            = {
        "name" = "uoc"
    }
}