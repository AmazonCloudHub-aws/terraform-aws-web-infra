# Create EC2 Instance - Amazon2 Linux
resource "aws_instance" "my-ec2-vm" {
  ami           = data.aws_ami.amzlinux.id 
  instance_type = var.instance_type
  count = 1
  user_data = file("apache-install.sh")  
  vpc_security_group_ids = [aws_security_group.vpc-ssh.id, aws_security_group.vpc-web.id]
  tags = {
    "Name" = "Terraform-Cloud-${count.index}"
  }
}

# Create Security Group - SSH Traffic
resource "aws_security_group" "vpc-ssh" {
  name        = "vpc-ssh-${terraform.workspace}"
  description = "Dev VPC SSH"
  ingress {
    description = "Allow Port 22"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Allow all ip and ports outboun"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create Security Group - Web Traffic
resource "aws_security_group" "vpc-web" {
  name        = "vpc-web-${terraform.workspace}"
  description = "Dev VPC web"
  ingress {
    description = "Allow Port 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Port 443"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all ip and ports outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

# Elastic IP for the EC2 Instance
# Assigns a static public IP address to ensure consistent access to the instance.
resource "aws_eip" "my_ec2_eip" {
  instance = aws_instance.my-ec2-vm.id
}

# EBS Volume for Additional Storage
# Creates an additional EBS volume for persistent storage needs beyond instance storage.
resource "aws_ebs_volume" "my_ec2_volume" {
  availability_zone = aws_instance.my-ec2-vm.availability_zone
  size              = 20 # Size in GiB
}

# Attaches the created EBS volume to the EC2 instance.
resource "aws_volume_attachment" "my_ec2_volume_attach" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.my_ec2_volume.id
  instance_id = aws_instance.my-ec2-vm.id
}

# CloudWatch Logs for Monitoring
# Configures a log group in CloudWatch for logging and monitoring instance activities.
resource "aws_cloudwatch_log_group" "my_ec2_log_group" {
  name              = "/aws/instance/my-ec2-vm"
  retention_in_days = 14 # Log retention policy in days
}

# Auto Scaling Group for High Availability
# Defines a launch configuration used by the auto-scaling group to ensure the right instance configuration.
resource "aws_launch_configuration" "my_app_lc" {
  name          = "my-app-launch-configuration"
  image_id      = data.aws_ami.amzlinux.id
  instance_type = var.instance_type

  # Ensures the old launch configuration is destroyed before creating a new one.
  lifecycle {
    create_before_destroy = true
  }
}

# Auto-scaling group to automatically adjust the number of instances based on load.
resource "aws_autoscaling_group" "my_app_asg" {
  launch_configuration = aws_launch_configuration.my_app_lc.name
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = [aws_subnet.my_subnet.id] # Replace with actual subnet IDs

  # Tags instances for easier identification and management.
  tag {
    key                 = "Name"
    value               = "my-app-instance"
    propagate_at_launch = true
  }
}

# Application Load Balancer for Traffic Distribution
# Sets up an ALB to distribute incoming traffic across multiple instances.
resource "aws_lb" "my_web_alb" {
  name               = "my-web-load-balancer"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.my_subnet.id] 

  security_groups = [aws_security_group.vpc-web.id]
}

# Target group for routing requests to the appropriate instances.
resource "aws_lb_target_group" "my_web_tg" {
  name     = "my-web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id 
}

# Listener to forward web traffic to the target group.
resource "aws_lb_listener" "my_web_listener" {
  load_balancer_arn = aws_lb.my_web_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_web_tg.arn
  }
}

# IAM Role for EC2 Instance
# Creates an IAM role with policies granting necessary permissions for the instance.
resource "aws_iam_role" "my_ec2_iam_role" {
  name = "my-ec2-iam-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com",
      },
    }],
  })
}

