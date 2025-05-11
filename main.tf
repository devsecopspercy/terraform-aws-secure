provider "aws" {
  region = "us-east-1"
}


# Genera una clave privada RSA de 4096 bits para autenticación SSH
resource "tls_private_key" "secure_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Crea un par de claves en AWS utilizando la clave pública generada
resource "aws_key_pair" "secure_key" {
  key_name   = "secure-key"
  public_key = tls_private_key.secure_key.public_key_openssh

  tags = {
    Name = "secure-key"
  }
}


# Guarda la clave privada generada en un archivo local
resource "local_file" "private_key" {
  content  = tls_private_key.secure_key.private_key_pem
  filename = "./secure-key.pem"
}

resource "aws_vpc" "secure_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "secure-vpc"
  }
}

# Subred pública para el Bastion Host
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.secure_vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

# Subred privada para la instancia segura
resource "aws_subnet" "secure_subnet" {
  vpc_id                  = aws_vpc.secure_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = false

  tags = {
    Name = "secure-subnet"
  }
}

# Internet Gateway para la VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.secure_vpc.id

  tags = {
    Name = "secure-igw"
  }
}

# Tabla de rutas para la subred pública
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.secure_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Asociar la tabla de rutas pública a la subred pública
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group para el Bastion Host
resource "aws_security_group" "bastion_sg" {
  vpc_id = aws_vpc.secure_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_IP/32"] # Reemplaza con tu IP específica
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-sg"
  }
}

# Instancia Bastion Host
resource "aws_instance" "bastion_host" {
  ami           = "ami-08b5b3a93ed654d19" # Cambia por una AMI válida
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true
  key_name      = aws_key_pair.secure_key.key_name

  tags = {
    Name = "bastion-host"
  }
}

# Security Group para la instancia privada
resource "aws_security_group" "secure_sg" {
  vpc_id = aws_vpc.secure_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [aws_security_group.bastion_sg.id] # Solo acceso desde el Bastion Host
  }

  ingress {
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
    Name = "secure-sg"
  }
}

# Instancia privada
resource "aws_instance" "secure_instance" {
  ami           = "ami-08b5b3a93ed654d19" # Cambia por una AMI válida
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.secure_subnet.id
  vpc_security_group_ids = [aws_security_group.secure_sg.id]
  associate_public_ip_address = false
  key_name      = aws_key_pair.secure_key.key_name
  
  root_block_device {
    volume_size           = 20
    encrypted             = true
  }

  tags = {
    Name = "secure-instance"
  }
}