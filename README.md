# tfmodule-aws-vpc

AWS VPC 서비스를 생성 하는 테라폼 모듈 입니다.

## Usage

```
module "ctx" {
  source = "git::https://code.bespinglobal.com/scm/op/tfmodule-context.git"
  context = {
    aws_profile = "terran"
    region      = "ap-northeast-2"
    project     = "apple"
    environment = "Production"
    owner       = "owner@academyiac.ml"
    team        = "DX"
    cost_center = "20211129"
    domain      = "academyiac.ml"
    pri_domain  = "applegoods.local"
  }
}

module "vpc" {
  source = "git::https://code.bespinglobal.com/scm/op/tfmodule-aws-vpc.git"

  context = module.ctx.context
  cidr    = "171.2.0.0/16"

  azs = [ data.aws_availability_zones.this.zone_ids[0], data.aws_availability_zones.this.zone_ids[1] ]

  public_subnet_names  = ["pub-a1", "pub-b1"]
  public_subnets       = ["171.2.11.0/24", "171.2.12.0/24"]
  public_subnet_suffix = "pub"

  enable_nat_gateway = true
  single_nat_gateway = true

  private_subnet_names = ["pri-a1", "pri-b1"]
  private_subnets      = ["171.2.31.0/24", "171.2.32.0/24"]

  depends_on = [module.ctx]
}


data "aws_availability_zones" "this" {
  state = "available"
}

```

### Dependencies Module
- Context 모듈은 [tfmodule-context](./tfmodule-context.md) 가이드를 참고 하세요.


## NAT Gateway 구성 시나리오
VPC 내의 서비스 및 인스턴스(EC2)가 외부의 www 자원을 액세스 하기 위해 배치 합니다.

- 하나의 NAT 를 배치 합니다.
```
    enable_nat_gateway = true
    single_nat_gateway = true
```

- 가용 영역(Availability Zone) 마다 NAT 를 배치 합니다.
```shell
    enable_nat_gateway = true
    one_nat_gateway_per_az = true
    single_nat_gateway = false
```
이 경우 가용 영역별 라우팅 테이블과 NAT 가 자동 매핑 됩니다.

- 서브 네트워크 마다 NAT 를 배치 합니다.
```shell
    enable_nat_gateway = true
    one_nat_gateway_per_az = false
    single_nat_gateway = false
```

## VPC Flow 로그
VPC 흐름 로그를 사용하면 특정 네트워크 인터페이스(ENI), 서브넷 또는 전체 VPC에 대한 IP 트래픽을 캡처할 수 있습니다.

```
  enable_flow_log           = true
  flow_log_destination_type = "s3"
  flow_log_destination_arn  = "<s3_bucket_arn>"
  flow_log_file_format      = "parquet"
  vpc_flow_log_tags = {
    Name = "my-vpc-flow-logs-s3-bucket"
  }
```
[vpc-flow-logs 샘플](https://github.com/terraform-aws-modules/terraform-aws-vpc/blob/master/examples/vpc-flow-logs/main.tf) 참고

## VPC IP Pool 확장
IP 주소 풀을 확장하기 위해 VP C와 연결할 보조 CIDR 블록을 정의 합니다.  
애플리케이션 배치를 위한 대상 그룹의 타겟 유형이 IP 이거나, EKS 등의 컨테이너가 다수 올라오게 되면 IP 가 부족할 수 있는데 여기에 대응하기위해 IP 풀을 확장 합니다.
```
    cidr                  = "172.0.0.0/16"
    secondary_cidr_blocks = ["172.1.0.0/16", "172.2.0.0/16"]
```
[vpc-secondary_cidr_blocks 샘플](https://github.com/terraform-aws-modules/terraform-aws-vpc/blob/master/examples/secondary-cidr-blocks/main.tf) 참고


## NACL 방화벽 정책 참고
```
locals {
  network_acls = {
    default_inbound = [
      {
        rule_number = 900
        rule_action = "allow"
        from_port   = 1024
        to_port     = 65535
        protocol    = "tcp"
        cidr_block  = "0.0.0.0/0"
      },
    ]
    default_outbound = [
      {
        rule_number = 900
        rule_action = "allow"
        from_port   = 32768
        to_port     = 65535
        protocol    = "tcp"
        cidr_block  = "0.0.0.0/0"
      },
    ]
}

module "vpc" {
  ...
  public_dedicated_network_acl = true
  public_inbound_acl_rules  = local.network_acls["default_inbound"]
  public_outbound_acl_rules = local.network_acls["default_outbound"]
  ...
}  
```
[NACL 샘플](https://github.com/terraform-aws-modules/terraform-aws-vpc/blob/master/examples/network-acls/main.tf) 참고


## VPN Gateway 를 통한 외부 네트워크간 연결
온-프레미스 또는 다른 CSP 벤더의 VPN 게이트웨이를 VPC 에 연결 할 수 있습니다.
```
resource "aws_vpn_gateway" "main" {
  vpc_id = "my-vpc"
  tags = {}
}

resource "aws_vpn_gateway_route_propagation" "main" {
  route_table_id = "rtb-0052b18f3b766dd5f" # VPC 의 라우팅 테이블 아이디
  vpn_gateway_id = aws_vpn_gateway.main.id
}

resource "aws_customer_gateway" "azure" {
  bgp_asn    = 65000
  ip_address = "211.12.31.33" # Azure 의 public 게이트웨이 아이피
  type       = "ipsec.1"
  tags = {}
}

# VPC 의 VPN 게이트웨이와 Azure 의 Public 게이트웨이의 연결 
resource "aws_vpn_connection" "azure" {
  vpn_gateway_id      = aws_vpn_gateway.main.id
  customer_gateway_id = aws_customer_gateway.azure.id
  type                = "ipsec.1"
  static_routes_only  = true
  tags = {}
}

resource "aws_vpn_connection_route" "azure" {
  vpn_connection_id      = aws_vpn_connection.azure.id
  destination_cidr_block = "10.2.1.0/24"
}
```

## Input Variables

| Name                                            | Description                                                         | Type | Example | Required |
|-------------------------------------------------|---------------------------------------------------------------------|------|---------|:--------:|
| create_vpc                                      | VPC 를 생성할지 여부입니다.                                                   | bool | true | No |
| cidr                                            | VPC CIDR 블럭을 정의 합니다.                                                | string | "172.11.0.0/16"| Yes |
| secondary_cidr_blocks                           | IP 주소 풀을 확장하기 위해 VP C와 연결할 보조 CIDR 블록을 정의 합니다.                      | list(string) | ["10.1.0.0/16", "10.2.0.0/16"] | No |
| public_subnets                                  | Public 서브넷의 CIDR 블럭을 정의 합니다.                                        | list(string)  | ["10.1.111.0/24", "10.1.112.0/24"] | No |
| public_subnet_names                             | Public 서브넷의 이름을 정의 합니다.                                             | list(string)  | ["pub-a1", "pub-b2"] | No |
| public_subnet_suffix                            | Public 서브넷의 접미어 입니다.                                                | string | "pub" | No |
| public_subnet_tags                              | Public 서브넷에 추가 할 태그 속성 입니다.                                         | map(string) | { Key1 = "Value1" } | No |
| private_subnets                                 | Private 서브넷의 CIDR 블럭을 정의 합니다.                                       | list(string)  | ["10.1.21.0/24", "10.1.22.0/24"] | No |
| private_subnet_names                            | Private 서브넷의 이름을 정의 합니다.                                            | list(string)  | ["pri-a1", "pri-b2"] | No |
| private_subnet_suffix                           | Private 서브넷의 접미어 입니다.                                               | string | "pri" | No |
| private_subnet_tags                             | Private 서브넷에 추가 할 태그 속성 입니다.                                        | map(string) | { Key1 = "Value1" } | No |
| database_subnets                                | 데이터베이스 서브넷의 CIDR 블럭을 정의 합니다.                                        | list(string)  | ["10.1.91.0/24", "10.1.92.0/24"] | No |
| database_subnet_names                           | 데이터베이스 서브넷의 이름을 정의 합니다.                                             | list(string)  | ["data-a1", "data-b2"] | No |
| database_subnet_suffix                          | 데이터베이스 서브넷의 접미어 입니다.                                                | string | "data" | No |
| database_subnet_tags                            | 데이터베이스 서브넷에 추가 할 태그 속성 입니다.                                         | map(string) | { Key1 = "Value1" } | No |
| database_subnet_group_tags                      | 데이터베이스 서브넷 그룹에 추가 할 태그 속성 입니다.                                      | map(string) | { Key1 = "Value1" } | No |
| intra_subnets                                   | Intranet 서브넷의 CIDR 블럭을 정의 합니다.                                      | list(string)  |  ["10.1.81.0/24", "10.1.82.0/24"] | No |
| intra_subnet_names                              | Intranet 서브넷의 이름을 정의 합니다.                                           | list(string)  | ["int-a1", "int-b2"] | No |
| intra_subnet_suffix                             | Intranet 서브넷의 접미어 입니다.                                              | string | "int" | No |
| intra_subnet_tags                               | Intranet 서브넷에 추가 할 태그 속성 입니다.                                       | map(string) | { Key1 = "Value1" } | No |
| create_database_subnet_route_table              | 데이터베이스 서브넷용 라우팅 테이블 생성 여부를 설정합니다.                                   | bool | false | No |
| create_database_subnet_group                    | RDS 전용 서브넷 생성 여부입니다. database_subnets 이 정의된 경우에만 반응 합니다.            | bool | true | No |
| create_database_internet_gateway_route          | 공용 데이터베이스 액세스를 위한 인터넷 게이트웨이를 생성 할 것인지 여부를 설정합니다.                    | bool | false | No |
| create_database_nat_gateway_route               | 데이터베이스 서브넷에 대한 인터넷 액세스를 위해 전용 NAT 를 생성해야 하는지 여부를 설정합니다.             | bool | false | No |
| azs                                             | 가용 영역 아이디 목록 입니다. 가용 영역은 AWS Region 마다 다르며, EC2 콘솔 화면에서 확인할 수 있습니다. | list(string)  |  ["apne2-az1", "apne2-az2"] | No |
| enable_dns_hostnames                            | VPC 에서 DNS 호스트 이름 검색을 활성화 할 것인지 여부입니다.                              | bool | true | No |
| enable_dns_support                              | VPC 에서 DNS 지원을 활성화 할 것인지 여부입니다.                                     | bool | true | No |
| enable_nat_gateway                              | NAT 게이트웨이를 생성할 것인지 여부입니다.                                           | bool | false | No |
| single_nat_gateway                              | 하나의 NAT 게이트웨이를 생성할 것인지 여부입니다.                                       | bool | false | No |
| one_nat_gateway_per_az                          | 가용 영역별로 NAT 게이트웨이를 생성할 것인지 여부입니다.                                   | bool | false | No |
| customer_gateways                               | 고객 게이트웨이 맵(BGP ASN 및 게이트웨이의 인터넷 라우팅 가능한 외부 IP 주소)을 정의 합니다.          | map(map(any)) | <pre>customer_gateways = {<br>  IP1 = {<br>    bgp_asn = 65112<br>    ip_address = "1.2.3.4"<br>    device_name = "some_name"<br>  },<br>  IP2 = {<br>    bgp_asn = 65112<br>    ip_address = "5.6.7.8"<br>  }<br>}</pre> | No |
| enable_vpn_gateway                              | 신규 VPN Gateway 리소스를 생성하여 VPC 에 연결할 것 인지 여부입니다.                      | bool | false | No |
| vpn_gateway_id                                  | VPC 에 추가 할 VPN 게이트웨이 아이디 입니다.                                       | string | example | No |
| tags                                            | VPC 및 연관된 리소스에 추가할 tag 속성 입니다.                                      | map(any) | { Project = "startek" } | No |
| vpc_tags                                        | VPC 리소스에 추가할 tag 속성 입니다.                                            | map(any) | { Name = "my-vpc" } | No |
| public_acl_tags                                 | Public ACL 리소스에 추가할 tag 속성 입니다.                                     | map(any) | { Key = "my-value-1" } | No |
| private_acl_tags                                | Private ACL 리소스에 추가할 tag 속성 입니다.                                    | map(any) | { Key = "my-value-1" } | No |
| intra_acl_tags                                  | 인트라넷 ACL 리소스에 추가할 tag 속성 입니다.                                       | map(any) | { Key = "my-value-1" } | No |
| database_acl_tags                               | 데이터베이스 ACL 리소스에 추가할 tag 속성 입니다.                                     | map(any) | { Key = "my-value-1" } | No |
| customer_gateway_tags                           | 커스터머 GW 리소스에 추가할 tag 속성 입니다.                                        | map(any) | { Key = "my-value-1" } | No |
| vpn_gateway_tags                                | VPN GW 리소스에 추가할 tag 속성 입니다.                                         | map(any) | { Key = "my-value-1" } | No |
| vpc_flow_log_tags                               | VPC Flow 리소스에 추가할 tag 속성 입니다.                                       | map(any) | { Key = "my-value-1" } | No |
| manage_default_network_acl                      | 기본 NACL 정책을 적용할지 여부입니다.                                             | bool | false | No |
| default_network_acl_name                        | 기본 NACL 이름 입니다.                                                     | string | "my-nacl" | No |
| default_network_acl_tags                        | 기본 NACL 태그 속성 입니다.                                                  | map(any) | { Key = "my-value-1" } | No |
| public_dedicated_network_acl                    | 공용 서브넷에 대한 전용 네트워크 ACL 및 사용자 지정 규칙을 사용할지 여부 입니다.                    | bool | false | No |
| private_dedicated_network_acl                   | Private 서브넷에 대한 전용 네트워크 ACL 및 사용자 지정 규칙을 사용할지 여부 입니다.               | bool | false | No |
| intra_dedicated_network_acl                     | Intranet 서브넷에 대한 전용 네트워크 ACL 및 사용자 지정 규칙을 사용할지 여부 입니다.              | bool | false | No |
| database_dedicated_network_acl                  | 데이터베이 서브넷에 대한 전용 네트워크 ACL 및 사용자 지정 규칙을 사용할지 여부 입니다.                 | bool | false | No |
| default_security_group_name                     | VPC 에 포함될 기본 보안 그룹 이름 입니다.                                          | string | "my-default-vpc-sg" | No |
| default_security_group_ingress                  | 기본 보안 그룹의 Ingress 룰 입니다.                                            | list(map(string)) | <pre>[<br>  {<br>    cidr_blocks = ["172.11.21.0/24"]<br>    description = "SSH"<br>    from_port   = "22"<br>    to_port     = "22"<br>    protocol    = "tcp"<br>  },<br>  {<br>    cidr_blocks = ["172.11.21.0/24"]<br>    description = "TLS"<br>    from_port   = "443"<br>    to_port     = "443"<br>    protocol    = "tcp"<br>  }<br>]</pre> | No |
| default_security_group_egress                   | 기본 보안 그룹의 Egress 룰 입니다.                                             | list(map(string)) | <pre>[<br>  {<br>    cidr_blocks = "0.0.0.0/0"<br>    description = "Outbound HTTP"<br>    from_port   = "80"<br>    to_port     = "80"<br>    protocol    = "tcp"<br>  },<br>]</pre> | No |
| enable_flow_log                                 | VPC Flow log 생성 여부입니다.                                              | bool | false | No |
| flow_log_destination_type                       | VPC Flow Logs 의 데이터가 적재되는 타겟 입니다. (s3, cloud-watch-logs)            | string | "cloud-watch-logs" | No |
| flow_log_destination_arn                        | VPC Flow Logs 데이터가 적재될 대상 리소스 ARN 입니다. (s3, cloud-watch-logs) | string | - | No |
| flow_log_format                                 | VPC Flow Logs 의 적재 메시지 포멧입니다.                                       | string | "" | No |
| flow_log_traffic_type                           | VPC Flow Logs 의 네트워크 전송 트래픽 유형입니다. (ACCEPT, REJECT, ALL)            | string | "ALL" | No |
| flow_log_max_aggregation_interval               | VPC Flow Logs 의 최대 수집 간격 입니다. | number | 600 | No |
| flow_log_file_format                            | VPC Flow Logs 의 데이터가 적재되는 파일 포멧입니다.(plain-text, parquet)            | string | "parquet" | No |
| create_flow_log_cloudwatch_log_group            | VPC Flow Logs용 CloudWatch 로그 그룹 생성 여부입니다.                           | bool | false | No |
| create_flow_log_cloudwatch_iam_role             | VPC Flow Logs용 CloudWatch IAM 롤 생성 여부입니다.                           | bool | false | No |
| flow_log_cloudwatch_iam_role_arn                | VPC Flow Logs용 CloudWatch IAM 롤의 ARN 입니다. | string | - | No |
| flow_log_cloudwatch_log_group_name_prefix       | VPC Flow Logs 용 Cloud CloudWatch 로그 그룹 경로 접두어 입니다. | string | "/aws/vpc-flow-log/" | No |
| flow_log_cloudwatch_log_group_retention_in_days | VPC Flow Logs 용 Cloud CloudWatch 로그 그룹의 데이터 보관일 수 입니다. | number | 90 | No |
| flow_log_cloudwatch_log_group_kms_key_id        | VPC Flow Logs 용 Cloud CloudWatch 로그 그룹 적재에 사용할 KMS 암호화 키 입니다. | string | - | No |
| create_private_domain_hostzone                  | Route53 private host-zone 에 private domain 레코드를 생성할지 여부입니다.. | bool | false | No |
| context                                         | 프로젝트에 관한 리소스를 생성 및 관리에 참조 되는 정보로 표준화된 네이밍 정책 및 리소스를 위한 속성 정보를 포함하며 이를 통해 데이터 소스 참조에도 활용됩니다. | object({}) | - | Yes |
| _________________________________               | ____________________________________________________ | _ | _ | _ |


## Outputs

| Name | Description |
|------|-------------|
| azs  |	A list of availability zones specified as argument to this module  |
| cgw_arns  |	List of ARNs of Customer Gateway  |
| cgw_ids  |	List of IDs of Customer Gateway  |
| database_internet_gateway_route_id  |	ID of the database internet gateway route.  |
| database_ipv6_egress_route_id  |	ID of the database IPv6 egress route.  |
| database_nat_gateway_route_ids  |	List of IDs of the database nat gateway route.  |
| database_network_acl_arn  |	ARN of the database network ACL  |
| database_network_acl_id  |	ID of the database network ACL  |
| database_route_table_association_ids  |	List of IDs of the database route table association  |
| database_route_table_ids  |	List of IDs of database route tables  |
| database_subnet_arns  |	List of ARNs of database subnets  |
| database_subnet_group  |	ID of database subnet group  |
| database_subnet_group_name  |	Name of database subnet group  |
| database_subnets  |	List of IDs of database subnets  |
| database_subnets_cidr_blocks  |	List of cidr_blocks of database subnets  |
| database_subnets_ipv6_cidr_blocks  |	List of IPv6 cidr_blocks of database subnets in an IPv6 enabled VPC  |
| default_network_acl_id  |	The ID of the default network ACL  |
| default_route_table_id  |	The ID of the default route table  |
| default_security_group_id  |	The ID of the security group created by default on VPC creation  |
| default_vpc_arn  |	The ARN of the Default VPC  |
| default_vpc_cidr_block  |	The CIDR block of the Default VPC  |
| default_vpc_default_network_acl_id  |	The ID of the default network ACL of the Default VPC  |
| default_vpc_default_route_table_id  |	The ID of the default route table of the Default VPC  |
| default_vpc_default_security_group_id  |	The ID of the security group created by default on Default VPC creation  |
| default_vpc_enable_dns_hostnames  |	Whether or not the Default VPC has DNS hostname support  |
| default_vpc_enable_dns_support  |	Whether or not the Default VPC has DNS support  |
| default_vpc_id  |	The ID of the Default VPC  |
| default_vpc_instance_tenancy  |	Tenancy of instances spin up within Default VPC  |
| default_vpc_main_route_table_id  |	The ID of the main route table associated with the Default VPC  |
| dhcp_options_id  |	The ID of the DHCP options  |
| egress_only_internet_gateway_id  |	The ID of the egress only Internet Gateway  |
| igw_arn  |	The ARN of the Internet Gateway  |
| igw_id  |	The ID of the Internet Gateway  |
| intra_network_acl_arn  |	ARN of the intra network ACL  |
| intra_network_acl_id  |	ID of the intra network ACL  |
| intra_route_table_association_ids  |	List of IDs of the intra route table association  |
| intra_route_table_ids  |	List of IDs of intra route tables  |
| intra_subnet_arns  |	List of ARNs of intra subnets  |
| intra_subnets  |	List of IDs of intra subnets  |
| intra_subnets_cidr_blocks  |	List of cidr_blocks of intra subnets  |
| intra_subnets_ipv6_cidr_blocks  |	List of IPv6 cidr_blocks of intra subnets in an IPv6 enabled VPC  |
| name  |	The name of the VPC specified as argument to this module  |
| nat_ids  |	List of allocation ID of Elastic IPs created for AWS NAT Gateway  |
| nat_public_ips  |	List of public Elastic IPs created for AWS NAT Gateway  |
| natgw_ids  |	List of NAT Gateway IDs  |
| outpost_network_acl_arn  |	ARN of the outpost network ACL  |
| outpost_network_acl_id  |	ID of the outpost network ACL  |
| outpost_subnet_arns  |	List of ARNs of outpost subnets  |
| outpost_subnets  |	List of IDs of outpost subnets  |
| outpost_subnets_cidr_blocks  |	List of cidr_blocks of outpost subnets  |
| outpost_subnets_ipv6_cidr_blocks  |	List of IPv6 cidr_blocks of outpost subnets in an IPv6 enabled VPC  |
| private_ipv6_egress_route_ids  |	List of IDs of the ipv6 egress route.  |
| private_nat_gateway_route_ids  |	List of IDs of the private nat gateway route.  |
| private_network_acl_arn  |	ARN of the private network ACL  |
| private_network_acl_id  |	ID of the private network ACL  |
| private_route_table_association_ids  |	List of IDs of the private route table association  |
| private_route_table_ids  |	List of IDs of private route tables  |
| private_subnet_arns  |	List of ARNs of private subnets  |
| private_subnets  |	List of IDs of private subnets  |
| private_subnets_cidr_blocks  |	List of cidr_blocks of private subnets  |
| private_subnets_ipv6_cidr_blocks  |	List of IPv6 cidr_blocks of private subnets in an IPv6 enabled VPC  |
| public_internet_gateway_ipv6_route_id  |	ID of the IPv6 internet gateway route.  |
| public_internet_gateway_route_id  |	ID of the internet gateway route.  |
| public_network_acl_arn  |	ARN of the public network ACL  |
| public_network_acl_id  |	ID of the public network ACL  |
| public_route_table_association_ids  |	List of IDs of the public route table association  |
| public_route_table_ids  |	List of IDs of public route tables  |
| public_subnet_arns  |	List of ARNs of public subnets  |
| public_subnets  |	List of IDs of public subnets  |
| public_subnets_cidr_blocks  |	List of cidr_blocks of public subnets  |
| public_subnets_ipv6_cidr_blocks  |	List of IPv6 cidr_blocks of public subnets in an IPv6 enabled VPC  |
| this_customer_gateway  |	Map of Customer Gateway attributes  |
| vgw_arn  |	The ARN of the VPN Gateway  |
| vgw_id  |	The ID of the VPN Gateway  |
| vpc_arn  |	The ARN of the VPC  |
| vpc_cidr_block  |	The CIDR block of the VPC  |
| vpc_enable_dns_hostnames  |	Whether or not the VPC has DNS hostname support  |
| vpc_enable_dns_support  |	Whether or not the VPC has DNS support  |
| vpc_flow_log_cloudwatch_iam_role_arn  |	The ARN of the IAM role used when pushing logs to Cloudwatch log group  |
| vpc_flow_log_destination_arn  |	The ARN of the destination for VPC Flow Logs  |
| vpc_flow_log_destination_type  |	The type of the destination for VPC Flow Logs  |
| vpc_flow_log_id  |	The ID of the Flow Log resource  |
| vpc_id  |	The ID of the VPC  |
| vpc_instance_tenancy  |	Tenancy of instances spin up within VPC  |
| vpc_ipv6_association_id  |	The association ID for the IPv6 CIDR block  |
| vpc_ipv6_cidr_block  |	The IPv6 CIDR block  |
| vpc_main_route_table_id  |	The ID of the main route table associated with this VPC  |
| vpc_owner_id  |	The ID of the AWS account that owns the VPC  |
| vpc_secondary_cidr_blocks  |	List of secondary CIDR blocks of the VPC  |

