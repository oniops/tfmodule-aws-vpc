# tfmodule-aws-vpc

AWS VPC와 부속 네트워크 리소스를 한 번의 호출로 만드는 재사용 Terraform 모듈이다. 여러 워크로드 스택을 하나의 Platform VPC에 수평으로 수용하고, 스택마다 독립된 Multi-AZ 서브넷 집합으로 격리한다. 요구사항은 `requirements/requirements/ 문서 세트`이 정의하며 이 README는 사용법과 입출력 표만 담는다.

만드는 리소스: VPC(보조 CIDR, IPv6), 서브넷, Route Table과 경로, Internet Gateway, Egress-only IGW, NAT Gateway·EIP, ENI, Security Group과 룰, Network ACL과 룰, DB·ElastiCache·Redshift·MemoryDB Subnet Group, VPC Endpoint(Gateway·Interface)와 Endpoint SG, VGW·CGW, Flow Log(목적지마다 1개), Private Hosted Zone, DHCP Options, 기본 SG·RT·NACL 채택.

## 설계 원칙

- **명시 선언**: Route Table은 `route_tables`에 목적지 → 대상으로 직접 적고, 모든 서브넷이 `route_table` 키로 그중 하나를 가리킨다. 모듈은 경로를 도출하지 않는다.
- **Role 계층 없음**: 스택 서브넷은 이름을 키로 하는 평면 Map이다. 계층은 이름으로, 성격은 가리키는 Route Table의 기본 경로로 드러난다.
- **안정 키**: 모든 리소스는 `for_each`와 호출자가 정한 이름을 키로 만든다. 항목을 더하거나 빼도 다른 리소스에 변경이 생기지 않는다.
- **모듈 소유는 키로, 호출자 소유는 ID로**: 경로 대상은 `gateway`(igw·eigw·vgw), `nat_gateway`(키), `eni`(키), `network_interface_id`(호출자 ENI ID) 중 하나다.
- **외부 확장 안전**: 경로와 SG 룰은 인라인 블록이 아닌 독립 리소스라, 다른 모듈(Peering 등)이 경로나 룰을 더해도 이 모듈의 plan이 흔들리지 않는다.

## Usage

`context`는 [tfmodule-context](https://github.com/oniops/tfmodule-context) `v1.3.5`의 출력을 그대로 받는다. 아래는 2 AZ, 워크로드 스택 1개, AZ별 NAT 1개의 최소 구성이다.

```hcl
module "ctx" {
  source      = "git::https://github.com/oniops/tfmodule-context.git?ref=v1.3.5"
  context     = var.context
  team        = "DevOps"
  cost_center = 1000
}

module "vpc" {
  source  = "git::https://github.com/oniops/tfmodule-aws-vpc.git?ref=<tag>"
  context = module.ctx.context

  vpc_cidr = "10.230.0.0/16"

  route_tables = {
    pub    = { routes = { "0.0.0.0/0" = { gateway = "igw" } } }
    pri-a1 = { routes = { "0.0.0.0/0" = { nat_gateway = "a1" } } }
    pri-c1 = { routes = { "0.0.0.0/0" = { nat_gateway = "c1" } } }
    iso    = {}
  }

  nat_gateways = {
    a1 = { public_subnet = "pub-a1" }
    c1 = { public_subnet = "pub-c1" }
  }

  shared_public = {
    subnets = {
      pub-a1 = { az = "apne2-az1", cidr = "10.230.0.0/24", route_table = "pub" }
      pub-c1 = { az = "apne2-az3", cidr = "10.230.1.0/24", route_table = "pub" }
    }
  }

  stack_subnets = {
    web = {
      tags = { Stack = "web" }
      subnets = {
        app-a1  = { az = "apne2-az1", cidr = "10.230.30.0/24", route_table = "pri-a1" }
        app-c1  = { az = "apne2-az3", cidr = "10.230.31.0/24", route_table = "pri-c1" }
        data-a1 = { az = "apne2-az1", cidr = "10.230.40.0/24", route_table = "iso" }
        data-c1 = { az = "apne2-az3", cidr = "10.230.42.0/24", route_table = "iso" }
      }
      db_subnet_group = { data = ["data-a1", "data-c1"] }
    }
  }

  vpc_endpoints = { gateway = ["s3"] }
  private_dns   = {}
  tags          = { Platform = "dxplat" }
}
```

목적지가 여러 곳인 Flow Log 는 `destinations` 에 항목을 더한다. 로그 그룹·버킷·Delivery Stream 과 그 IAM 롤은 모듈이 만들지 않고 ARN 만 참조한다(RSC-FLOW-08).

```hcl
  flow_log = {
    destinations = {
      s3 = {
        log_destination_type = "s3"
        log_destination_arn  = "arn:aws:s3:::org-vpc-flowlogs/platform"
        destination_options  = {} # parquet + Hive 파티션 + 시간별 파티션
      }
      cloudwatch = {
        log_destination_type = "cloud-watch-logs"
        log_destination_arn  = "arn:aws:logs:ap-northeast-2:111122223333:log-group:/vpc/flowlogs:*"
        iam_role_arn         = "arn:aws:iam::111122223333:role/flowlogs-to-cloudwatch"
      }
    }
  }
```

각 입력의 전체 필드와 기본값은 `variables.tf`의 `description`에 호출 예시와 함께 있다. 스택 전용 Public, 보조 CIDR, NAT 인스턴스 ENI, NACL, VGW·CGW, IPv6, 3 AZ EKS 구성처럼 기능을 조합한 검증 입력 다섯 가지의 구성은 `requirements/REQUIREMENTS.md` 5.1절이 정의한다. EKS 스택에 필요한 서브넷 태그는 `requirements/ARCHITECTURE.md`에 있다.

## Input Variables

타입의 정본은 `requirements/REQUIREMENTS.md` 4절과 4.3절이다. 아래 표는 요약이며, 각 변수의 `description`에 호출 예시가 있다.

| 이름 | 타입 요약 | 기본값 | 설명 |
| --- | --- | --- | --- |
| `context` | `object` | 필수 | tfmodule-context 출력. `name_prefix`, `tags`, `region`, `pri_domain`을 쓴다 |
| `vpc_cidr` | `string` | 필수 | VPC 기본 IPv4 CIDR. 변경 시 재생성 |
| `secondary_cidrs` | `set(string)` | `[]` | 보조 IPv4 CIDR. CIDR 문자열이 리소스 키 |
| `enable_ipv6` | `bool` | `false` | Amazon 제공 IPv6 /56 할당. `false`면 모든 IPv6 입력이 plan 실패 |
| `shared_public` | `object({ tags, nacl, subnets })` | `null` | Shared Public Network. 서브넷은 `igw` 기본 경로를 가진 RT를 가리켜야 한다 |
| `vpc_endpoint_subnets` | `map(object)` | `{}` | Interface Endpoint ENI 전용 서브넷. 기본 경로 없는 RT, AZ당 1개 |
| `stack_subnets` | `map(object)` | `{}` | 워크로드 스택. 서브넷 평면 Map, 스택 NACL, Subnet Group 네 종류(`db_subnet_group`·`elasticache_subnet_group`·`redshift_subnet_group`·`memorydb_subnet_group`), 스택 태그 |
| `route_tables` | `map(object)` | `{}` | Route Table. `routes`는 목적지 CIDR → 대상(`gateway`·`nat_gateway`·`eni`·`network_interface_id` 중 하나), `propagate_vgw` |
| `nat_gateways` | `map(object)` | `{}` | NAT Gateway. `public_subnet`은 Shared Public 서브넷 이름, `eip_allocation_id`로 EIP 재사용 |
| `eni_interfaces` | `map(object)` | `{}` | 모듈이 만드는 ENI. NAT 인스턴스용은 `source_dest_check = false`. SG는 `security_group_names`(모듈 SG)와 `security_group_ids`(호출자 SG) 합집합 |
| `security_groups` | `map(object)` | `{}` | 모듈이 만드는 SG와 룰. 룰은 이름 키 Map이며 독립 리소스. 키 `vpce`는 예약 |
| `vpc_endpoints` | `object({ gateway, interface })` | `null` | Gateway Endpoint는 모든 RT에 연결, Interface Endpoint는 `vpc_endpoint_subnets`에 ENI 생성 |
| `vpn_gateway` | `object` | `null` | VGW 생성 또는 `existing_id` 연결. ASN은 문자열 |
| `customer_gateways` | `map(object)` | `{}` | Customer Gateway(`ipsec.1`). ASN은 문자열 |
| `flow_log` | `object({ destinations })` | `null` | VPC Flow Log. `destinations` 항목 하나가 Flow Log 하나(`cloud-watch-logs`·`s3`·`kinesis-data-firehose`). 목적지 리소스는 만들지 않고 ARN만 참조한다 |
| `private_dns` | `object` | `null` | Private Hosted Zone. `domain_name` 생략 시 `context.pri_domain` |
| `dhcp_options` | `object` | `null` | DHCP Options. `domain_name` 생략 시 `context.pri_domain` |
| `tags` | `map(string)` | `{}` | 모든 리소스에 적용하는 모듈 공통 태그 |

태그는 `merge(context.tags, tags, <인스턴스별 tags>, { Name })` 순서로 병합하고 `Name`은 보호 키다. plan에서 드러나지 않는 제약(미연결 ENI 경로, 룰 없는 SG, 기본 SG, `source_dest_check`)은 POLICIES 6.3절 표를 따른다.

## Outputs

복수 리소스는 리소스 키를 그대로 키로 갖는 Map이고, 없는 단일 리소스는 `null`이다.

| 출력 | 내용 |
| --- | --- |
| `vpc_id`, `vpc_arn`, `vpc_cidr_block`, `vpc_ipv6_cidr_block`, `vpc_owner_id` | VPC 속성 |
| `vpc_secondary_cidr_association_ids` | 보조 CIDR → 연관 ID |
| `igw_id`, `igw_arn`, `eigw_id` | 게이트웨이 |
| `default_security_group_id`, `default_network_acl_id`, `default_route_table_id`, `dhcp_options_id` | 기본 리소스 |
| `subnet_ids`, `subnet_arns`, `subnet_cidr_blocks`, `subnet_ipv6_cidr_blocks` | 서브넷 키(`shared-network/public/<name>`, `shared-network/vpce/<name>`, `<stack>/<name>`) → 값 |
| `shared_network` | Shared Public·VPC Endpoint 서브넷을 이름으로 모은 편의 출력 |
| `nat_gateway_ids`, `nat_eip_allocation_ids`, `nat_public_ips` | NAT 키 → 값 |
| `eni_ids`, `eni_arns`, `eni_private_ips` | ENI 키 → 값 |
| `security_group_ids`, `security_group_arns` | SG 키 → 값 |
| `route_table_ids`, `route_table_association_ids` | RT 키 → ID, 서브넷 키 → Association ID |
| `network_acl_ids`, `network_acl_arns` | NACL 키(`<stack>`, `shared-network/public`) → 값 |
| `stacks` | 스택별 `subnet_ids`(이름 → ID)와 네 유형의 `<type>_subnet_group_names`·`_arns`(`db`, `elasticache`, `redshift`, `memorydb`) |
| `vpc_endpoint_ids`, `vpc_endpoint_dns_entries`, `vpc_endpoint_security_group_id` | Endpoint |
| `vgw_id`, `vgw_arn`, `vgw_attachment_id` | VGW |
| `cgw_ids`, `cgw_arns` | CGW 키 → 값 |
| `flow_log_ids`, `flow_log_arns`, `flow_log_destination_arns` | Flow Log 목적지 키 → 값 |
| `private_zone_id`, `private_zone_name`, `private_zone_arn` | Private Hosted Zone |

## Shared Service 접근 정책 예시

모듈 요구사항이 아니라 호출자가 스택 NACL(REQUIREMENTS 6.8절)과 `security_groups`(3.6절)를 설계할 때 참고할 예시다. 모듈 기본 상태는 기본 NACL 전체 허용이고(RSC-DEF-03), 모듈이 만드는 SG 는 자기가 만든 ENI 와 Interface Endpoint 에 붙는 것뿐이다.

| 출발지 | 목적지 | 정책 |
| --- | --- | --- |
| Toolchain | Workload Management Endpoint | Allow |
| Workload | Toolchain | Default Deny |
| Workload | Observability Endpoint | Allow |
| Observability | Workload | 필요 시 제한적 Allow |
| Workload-A | Workload-B | Default Deny |

POLICIES 9.4절 `eks` 기준 입력의 `toolchain` 스택 NACL 이 "Workload → Toolchain Default Deny" 를 NACL 로 구현한 예다. NACL 은 상태 비저장이고 룰의 포트 범위가 목적지 포트이므로, Toolchain 이 시작한 연결의 응답(목적지 포트 32768~65535)만 워크로드 대역에서 허용하고 나머지는 deny 한다. 32768 이상 포트로 연 서비스는 NACL 로 막을 수 없으므로 Security Group 으로 막는다.

같은 정책을 모듈의 `security_groups` 로 표현하면 다음과 같다. 룰은 이름을 키로 하는 Map 이고 소스는 다섯 필드 중 하나만 적는다(RSC-SG-04). 모듈 SG 끼리는 `referenced_security_group_name` 으로, 호출자가 만든 SG 는 `referenced_security_group_id` 로 가리킨다.

```hcl
security_groups = {
  toolchain-endpoint = {
    description = "Toolchain internal endpoint ENI"

    # "Workload -> Toolchain Default Deny" 는 룰을 적지 않는 것으로 표현된다.
    # 필요한 대역·SG 만 열면 나머지는 자동으로 막힌다.
    ingress = {
      workload-https = { ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "10.100.32.0/19", description = "Workload management endpoint" }
      obsv-otlp      = { ip_protocol = "tcp", from_port = 4317, to_port = 4318, referenced_security_group_name = "obsv-collector", description = "Observability collector" }
    }

    egress = {
      https = { ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0", description = "Outbound HTTPS" }
    }

    tags = { ServiceRole = "toolchain" }
  }

  # 룰이 없는 SG. 두 방향 모두 차단이며 참조 대상으로만 쓴다(RSC-SG-05).
  obsv-collector = { description = "Observability collector ENI" }
}
```

NACL 과 다른 점이 둘이다.

- Security Group 은 상태 저장이라 응답 트래픽을 따로 열지 않는다. 위의 "Toolchain 이 시작한 연결의 응답" 을 NACL 에서는 32768~65535 로 열어야 하지만 SG 에서는 인바운드 룰 하나면 된다.
- "Default Deny" 가 룰을 적지 않는 것으로 표현된다. 모듈이 만든 SG 는 생성 시점에 AWS 기본 아웃바운드 허용 룰이 회수되므로, 아웃바운드가 필요하면 `egress` 를 반드시 적어야 한다(RSC-SG-05).

워크로드(EC2, ECS, EKS 노드, RDS)에 붙는 SG 는 이 모듈이 만들지 않는다. 위 예시는 모듈이 만든 ENI 에 붙일 SG 를 선언하는 형식을 보이는 것이고, 같은 형식을 워크로드 모듈에서도 쓸 수 있다.

## 검증

절차와 판정 기준은 `requirements/POLICIES.md` 5절이 정의한다.

```bash
terraform fmt -check *.tf
terraform init -backend=false && terraform validate
```

여기까지는 clone 직후 바로 돌아간다. 아래 두 단계는 검증 자산이 필요하다. 기준 입력(POLICIES 9.4절), `tests/*.tftest.hcl`(POLICIES 9.5절), `examples/<이름>/` 호출 스택은 `.gitignore`로 제외된 로컬 자산이라 저장소에 없으며, 요구사항 문서를 보고 로컬에서 만든 뒤 실행한다.

```bash
terraform test -filter=tests/<대상>.tftest.hcl \
  -var-file=requirements/<기준 입력>.tfvars -var-file=tests/context.tfvars
cd examples/<이름> && terraform init && terraform plan -var-file=../../requirements/<기준 입력>.tfvars
```

`apply`와 `destroy`는 이 저장소에서 실행하지 않는다. `terraform test`는 `mock_provider`로 실행해 AWS를 호출하지 않으므로 이 금지의 대상이 아니다. 검증 항목은 POLICIES 9.5절(`TST-01`~`TST-39`), 실패 케이스는 4.1절 표(`V-01`~`V-27`, `P-01`~`P-23`)를 따른다.
