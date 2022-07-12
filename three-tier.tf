terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region     = "us-east-1"
  access_key = AWS_ACCESS_KEY_ID
  secret_key = AWS_SECRET_ACCESS_KEY
}


### VPC variable

variable "vpc_cidr" {
  description = "default VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

### Availability Zone variable

variable "availability_zone_names" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

### Web Subnet CIDR

variable "web_subnet_cidr" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]

}

### Application Subnet CIDR

variable "application_subnet_cidr" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

### Database Subnet CIDR

variable "database_subnet_cidr" {
  type    = list(string)
  default = ["10.0.21.0/24", "10.0.22.0/24"]

}

### Database variables

variable "rds_instance" {
  type = map(any)
  default = {
    allocated_storage   = 10
    engine              = "mysql"
    engine_version      = "8.0.20"
    instance_class      = "db.t2.micro"
    multi_az            = true
    name                = "my_db"
    skip_final_snapshot = true
  }
}

### Create DB Variables
variable "user_information" {
  type = map(any)
  default = {
    username = "username"
    password = "password"
  }
  sensitive = true
}

### Instance variable 

variable "ami_id" {
  description = "default ami"
  type        = string
  default     = "ami-0cff7528ff583bf9a"
}

variable "instance_type" {
  description = "default instance type"
  type        = string
  default     = "t2.micro"
}
### Count variable

variable "item_count" {
  description = "default count used to set AZs and instances"
  type        = number
  default     = 2
}

### Create a VPC
resource "aws_vpc" "vpc-1" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "Demo VPC"
  }

}


### Create an Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc-1.id

  tags = {
    Name = "IGW"
  }

}

### Create a Web Facing Routing Table
resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.vpc-1.id


  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id

  }

  tags = {
    Name = "Public-Rt"
  }

}

### Create Subnet Association with Route Table
resource "aws_route_table_association" "a" {
  count          = var.item_count
  subnet_id      = aws_subnet.web-facing[count.index].id
  route_table_id = aws_route_table.public-rt.id
}

### Create Web Public Subnet
resource "aws_subnet" "web-facing" {
  count                   = var.item_count
  vpc_id                  = aws_vpc.vpc-1.id
  cidr_block              = var.web_subnet_cidr[count.index]
  availability_zone       = var.availability_zone_names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "web-${count.index + 1}"
  }

}

### Create Application Private Subnet
resource "aws_subnet" "application" {
  count                   = var.item_count
  vpc_id                  = aws_vpc.vpc-1.id
  cidr_block              = var.application_subnet_cidr[count.index]
  availability_zone       = var.availability_zone_names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "application-${count.index + 1}"
  }

}


### Create Database Private Subnet
resource "aws_subnet" "db" {
  count             = var.item_count
  vpc_id            = aws_vpc.vpc-1.id
  cidr_block        = var.database_subnet_cidr[count.index]
  availability_zone = var.availability_zone_names[count.index]

  tags = {
    Name = "db-${count.index + 1}"
  }

}

### Create External Load Balancer

resource "aws_lb" "external-lb" {
  name               = "External-LB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web-sg.id]
  subnets            = [aws_subnet.web-facing[0].id, aws_subnet.web-facing[1].id]

  enable_deletion_protection = true
}

### Create Internal Load Balancer

resource "aws_lb" "internal-lb" {
  name               = "Internal-LB"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app-sg.id]
  subnets            = [aws_subnet.application[0].id, aws_subnet.application[1].id]

  enable_deletion_protection = true
}

### Create an External Target Group

resource "aws_lb_target_group" "external-elb" {
  name     = "ALB-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc-1.id
}

### Create and Internal Target Group

resource "aws_lb_target_group" "internal-elb" {
  name     = "ILB-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc-1.id
}
### Create Target Group Attachment

resource "aws_lb_target_group_attachment" "external-elb1" {
  count            = var.item_count
  target_group_arn = aws_lb_target_group.external-elb.arn
  target_id        = aws_instance.webserver[count.index].id
  port             = 80

  depends_on = [
    aws_instance.webserver,
  ]
}

resource "aws_lb_target_group_attachment" "internal-elb1" {
  count            = var.item_count
  target_group_arn = aws_lb_target_group.internal-elb.arn
  target_id        = aws_instance.appserver[count.index].id
  port             = 80

  depends_on = [
    aws_instance.webserver,
  ]
}


### Create LB Listener

resource "aws_lb_listener" "external-elb" {
  load_balancer_arn = aws_lb.external-lb.arn
  port              = "80"
  protocol          = "HTTP"


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.external-elb.arn
  }
}

resource "aws_lb_listener" "internal-elb" {
  load_balancer_arn = aws_lb.internal-lb.arn
  port              = "80"
  protocol          = "HTTP"


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal-elb.arn
  }
}

### Create Security Groups

resource "aws_security_group" "web-sg" {
  name        = "Web-SG"
  description = "Allow HTTP Inbound Traffic"
  vpc_id      = aws_vpc.vpc-1.id

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Web-SG"
  }
}

### Create Web Server Security Group

resource "aws_security_group" "webserver-sg" {
  name        = "Webserver-SG"
  description = "Allow Inbound Traffic from ALB"
  vpc_id      = aws_vpc.vpc-1.id

  ingress {
    description     = "Allow traffic from web layer"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.web-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Webserver-SG"
  }
}

### Create Application Security Group

resource "aws_security_group" "app-sg" {
  name        = "App-SG"
  description = "Allow SSH Inbound Traffic"
  vpc_id      = aws_vpc.vpc-1.id

  ingress {
    description     = "SSH from VPC"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.web-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "App-SG"
  }
}
### Created Database Security Group

resource "aws_security_group" "database-sg" {
  name        = "Database-SG"
  description = "Allow Inbound Traffic from application layer"
  vpc_id      = aws_vpc.vpc-1.id

  ingress {
    description     = "Allow traffic from application layer"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.webserver-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Database-SG"
  }
}

### Create EC2 Instance
resource "aws_instance" "webserver" {
  count                  = var.item_count
  ami                    = var.ami_id
  instance_type          = var.instance_type
  availability_zone      = var.availability_zone_names[count.index]
  vpc_security_group_ids = [aws_security_group.webserver-sg.id]
  subnet_id              = aws_subnet.web-facing[count.index].id
  user_data              = file("install_apache.sh")

  tags = {
    Name = "Web Server-${count.index}"
  }
}

### Create App Instance
resource "aws_instance" "appserver" {
  count                  = var.item_count
  ami                    = var.ami_id
  instance_type          = var.instance_type
  availability_zone      = var.availability_zone_names[count.index]
  vpc_security_group_ids = [aws_security_group.app-sg.id]
  subnet_id              = aws_subnet.application[count.index].id

  tags = {
    Name = "App Server-${count.index}"
  }

}
### Create RDS Instance

resource "aws_db_instance" "default" {
  allocated_storage      = var.rds_instance.allocated_storage
  db_subnet_group_name   = aws_db_subnet_group.default.id
  engine                 = var.rds_instance.engine
  engine_version         = var.rds_instance.engine_version
  instance_class         = var.rds_instance.instance_class
  multi_az               = var.rds_instance.multi_az
  name                   = var.rds_instance.name
  username               = var.user_information.username
  password               = var.user_information.password
  skip_final_snapshot    = var.rds_instance.skip_final_snapshot
  vpc_security_group_ids = [aws_security_group.database-sg.id]

}

### Create RDS Subnet Group

resource "aws_db_subnet_group" "default" {
  name       = "main"
  subnet_ids = aws_subnet.db[count.index]

  tags = {
    name = "My DB subnet group"
  }
}

### Create ouput to print

output "lb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.external-lb.dns_name

}
