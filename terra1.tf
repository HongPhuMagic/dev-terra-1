terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
    }
  }
}


provider "aws" {
  region = "ca-central-1"
  access_key = ""  # var.cred_ac
  secret_key = ""  # var.cred_sc
}


# 1. Create vpc
resource "aws_vpc" "vpc1" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}


# 2. Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc1.id
}


# 3. Create Custom Route Table
resource "aws_route_table" "route-table1" {
  vpc_id = aws_vpc.vpc1.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "prod"
  }
}


# 4. Create a Subnet
resource "aws_subnet" "subnet-1" {
    vpc_id = aws_vpc.vpc1.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "ca-central-1a"

    tags = {
        Name = "cloud-ready"
    }
}


# 5. Associate subnet with Route Table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.route-table1.id
}


# 6. Create security group to allow port 22, 80, 443 (ports we need for webtraffic)
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    description = "HTTPS"
    from_port   = 443                            # range of ports 
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]                  
  }

  ingress {
    description = "HTTP"
    from_port   = 80                          
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]                  
  }

  ingress {
    description = "SSH"
    from_port   = 22                          
    to_port     = 22
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
    Name = "allow_web"
  }
}


# 7. Create a network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "web-server-sol" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]                       # give ip to the webserver
  security_groups = [aws_security_group.allow_web.id]

}


# 8. Assign an elastic IP to the network interface created in step 7. Elastic ip allows anyone on the internet to connect to
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-sol.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

output "server_public_ip" {
  value = aws_eip.one.public_ip
}


# 9. Create Ubuntu server and install/enable apache2
resource "aws_instance" "second-ec2" { 
  ami = "ami-0c2f25c1f66a1ff4d"
  instance_type = "t2.micro"
  availability_zone = "ca-central-1a"
  key_name          = "EC2 Tutorial"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-sol.id
  }
  
  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y"
      "sudo yum install apache2 -y"
      "sudo yum install git"
      "sudo mkdir /home/ec2-user/automate-prometheus-ansible"
      # "sudo mkdir /home/ec2-user/webapp"
      "sudo cd /home/ec2-user/automate-prometheus-ansible"
      "sudo git clone https://github.com/HongPhuMagic/automate-prometheus-ansible.git"
      # "sudo ansible -m role_node_setup.yml"
    ]
  }

  tags = {
    Name = "league_web"
  }

  connection {
    type = "ssh"
    user = "ec2-user"
    password = ""
    private_key = "home/nonr/AWS/cloud.pem"
  }
}


output "server_private_ip" {
  value = aws_instance.second-ec2.private_ip
}

output "server_id" {
  value = aws_instance.second-ec2.id
}






#user_data = <<-EOF
  #               #!/bin/bash
  #               sudo yum update -y
  #               sudo yum install apache2 -y
                
  #               sudo yum install docker -y 
  #               sudo service docker start
  #               sudo chmod 666 /var/run/docker.sock
                
  #               EOF
# sudo docker run -p 80:5000 bankai9415/lol-web-headless
