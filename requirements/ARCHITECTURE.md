# ARCHITECTURE — 어떤 모델로 표현하고 무엇을 주고받는가

> **문서 종류:** Terraform 모듈 아키텍처·구현 명세
> **모듈:** `tfmodule-aws-vpc`
> **답하는 질문:** 이 모듈은 어떤 모델로 VPC를 표현하는가. 호출자는 무엇을 입력하고 무엇을 돌려받는가. 코드는 어떻게 구성되고 검사는 어디에 놓이는가.
> **함께 읽기:** [REQUIREMENTS](REQUIREMENTS.md) — 왜 존재하고 무엇을 만족해야 하며 어떤 규칙을 강제하고 어떻게 검증하며 왜 그렇게 결정했는가

REQUIREMENTS가 정한 요구사항을 **어떤 구조로** 만족시키는지 정의한다. 이 문서는 모델(1~5절), 계약(6~11절), 구현(12~13절) 세 부분이다. 모델은 모듈이 세상을 바라보는 방식이고, 계약은 호출자와 주고받는 인터페이스이며, 구현은 그 계약을 코드로 옮기는 방식과 검사를 두는 자리다.

한 문장으로 요약하면 이렇다.

> **VPC 하나에 워크로드 스택을 수평으로 쌓고, 스택마다 전용 Multi-AZ 서브넷 집합으로 격리한다. 서브넷의 성격은 그 서브넷이 가리키는 Route Table의 기본 경로가 정하고, 계층은 호출자가 정한 이름이 나타낸다.**

## 목차

1. [전체 구조](#1-전체-구조)
2. [스택과 서브넷](#2-스택과-서브넷)
3. [라우팅](#3-라우팅)
4. [NAT](#4-nat)
5. [공유 서비스와 외부 연결](#5-공유-서비스와-외부-연결)
6. [리소스 키 체계](#6-리소스-키-체계)
7. [이름 규칙](#7-이름-규칙)
8. [입력 계약](#8-입력-계약)
9. [입력 검증과 검사 배치](#9-입력-검증과-검사-배치)
10. [출력 계약](#10-출력-계약)
11. [`context` 계약](#11-context-계약)
12. [코드 컨벤션](#12-코드-컨벤션)
13. [EKS 스택](#13-eks-스택)

---

## 1. 전체 구조

VPC는 여러 워크로드 스택을 수평적으로 수용하고, 각 스택은 독립적인 Multi-AZ Subnet Set으로 수직 격리한다. Toolchain, Observability 같은 Shared Service도 같은 구조의 스택이다(2.2절, 5.1절).

```text
Platform VPC
│
├─ Shared Public Network
│  ├─ Public Subnet / AZ-A, AZ-B, ...
│  └─ NAT Gateway, NAT 인스턴스용 ENI·Security Group, Internet-facing LB
│
├─ Workload Stack A            (서브넷 = 이름 + 배치 AZ + CIDR + 연결할 Route Table)
│  └─ Multi-AZ Subnet Set
├─ Workload Stack B
│  └─ Multi-AZ Subnet Set
├─ Workload Stack N            (Toolchain, Observability 등 Shared Service 스택도 같은 구조)
│  └─ Multi-AZ Subnet Set
│
└─ Shared Network Services
   ├─ Route Table, Internet Gateway, Egress-only IGW
   ├─ VPC Endpoint (Gateway, Interface + VPC Endpoint Subnet)
   ├─ Private DNS, DHCP Options
   └─ Flow Logs
```

특정 서비스명이나 업무 도메인에 종속되지 않아야 하며, 임의의 워크로드 스택을 선언형 입력만으로 추가·제거할 수 있어야 한다.

---

## 2. 스택과 서브넷

### 2.1 스택 모델

- 각 워크로드는 다른 워크로드와 공유하지 않는 전용 Subnet Set을 가져야 한다.
- VPC는 최소 2개, 권장 3개 AZ에 배치한다. AZ는 서브넷마다 그 서브넷 항목의 `az` 필드로 선언한다. 검사는 [REQUIREMENTS 6.2절](REQUIREMENTS.md#62-가용-영역)이 정의한다.
- 워크로드 스택의 추가·제거는 그 스택의 리소스만 생성·삭제하고 다른 스택과 Shared Network 리소스에 변경을 만들지 않는다. 수명주기 원칙은 [REQUIREMENTS 7.5절](REQUIREMENTS.md#75-수명주기-정책)이 정의한다.
- Secondary VPC CIDR 추가를 지원하여 향후 IP 확장에 대응할 수 있어야 한다.

### 2.2 서브넷 모델

서브넷은 스택 안에서 이름을 키로 하는 평면 Map으로 선언하며, 한 항목이 서브넷 하나다. 항목에는 배치 AZ(`az`), CIDR(`cidr`), 연결할 Route Table(`route_table`)이 모두 들어 있어 그 한 줄만 읽어도 서브넷이 어디에 놓이고 어디로 나가는지 알 수 있다. 서브넷 객체의 구조는 2.3절이, 리소스 키 체계는 6절이 정의한다.

- 모듈은 스택 서브넷에 Role이나 계층 구분을 두지 않는다. 서브넷의 **성격은 그 서브넷이 가리키는 Route Table의 `0.0.0.0/0` 경로**가 정하고(3절), **계층은 호출자가 정한 서브넷 이름**으로 나타낸다. `public`·`private`·`database`·`intra` 같은 Role 키, Role별 허용 경로 검사, Role별 필수 여부는 두지 않는다.
- 아래 표는 Route Table 성격별 권장 용도이며 모듈이 검사하는 제약이 아니다. 어느 스택 서브넷이든 선언된 어느 Route Table이든 가리킬 수 있다.

| 연결한 RT의 `0.0.0.0/0` | RT 성격 | 권장 용도 |
| --- | --- | --- |
| `igw` | Public | Internet-facing LB, 공인 IP를 직접 받는 워크로드. 스택 서브넷이 이 RT를 가리키면 그것이 스택 전용 Public Subnet이다. NAT Gateway는 Shared Public Subnet에만 배치한다(4절) |
| NAT(Gateway 또는 인스턴스 ENI) | Private | 워크로드 노드, Pod, Internal LB. OS 패치 등 외부 접근이 필요한 데이터 계층 |
| 경로 없음 | Isolated | 관리형 DB, ElastiCache 등 데이터 계층(권장), 내부 전용 서비스, VPC Endpoint Subnet. 패치는 S3·SSM Endpoint를 우선한다 |

- 경로 리소스는 Route Table 단위다. 서브넷을 하나 추가하면 그 서브넷과 Route Table Association만 생기고 Route Table·경로·다른 서브넷의 리소스는 변하지 않는다. NACL은 서브넷 단위가 아니라 스택당 1개다([REQUIREMENTS 6.8절](REQUIREMENTS.md#68-network-acl)).
- 스택이 VPC의 모든 AZ를 채우도록 강제하지 않는다. 스택 서브넷의 개수 요건은 RSC-SUB-10이 정의한다.
- 스택의 성격(워크로드, Toolchain, Observability, EKS 등)을 구분하는 입력(`type` 등)은 두지 않으며 태그로만 구별한다. 성격을 나타내는 태그(예: `ServiceRole`)와 EKS 등 외부 컨트롤러가 요구하는 태그는 모듈이 만들지 않고 호출자가 스택 `tags` 또는 서브넷 `tags`에 직접 정의한다. 13절은 EKS 스택에 필요한 태그 목록을 안내할 뿐 새 라우팅 규칙을 정의하지 않는다. 이 원칙은 이 항목이 유일한 정의다.
- 데이터 계층·격리 계층의 인바운드 제한은 스택 NACL 입력([REQUIREMENTS 6.8절](REQUIREMENTS.md#68-network-acl))과 워크로드 Security Group으로 구성한다. 모듈이 기본 룰을 강제하지 않는다.
- Shared Network의 `shared_public`과 `vpc_endpoint_subnets`는 스택 서브넷이 아니며, 각각 RSC-PUB-04, RSC-VPCE-07의 Route Table 제약을 받는다. 스택 서브넷에는 그런 제약이 없다.

### 2.3 서브넷 객체 구조

`shared_public.subnets`, `vpc_endpoint_subnets`, 스택 `subnets`는 모두 **서브넷 이름을 키로 하는 아래 객체의 Map**이다. 한 항목이 서브넷 하나이며, 그 항목만 읽어도 배치 AZ·CIDR·연결할 Route Table을 알 수 있다. 이 절이 서브넷 객체 구조의 유일한 정의다.

| 필드 | 타입 | 내용 |
| --- | --- | --- |
| (키) | 서브넷 이름 | 리소스 키의 마지막 마디이자 `Name` 태그의 가운데(2.1·7절). VPC 전체에서 유일해야 한다 |
| `az` | `string`, 필수 | 배치 AZ의 AZ ID. `availability_zone_id`에 그대로 적용한다 |
| `cidr` | `string`, 필수 | `cidr_block`에 그대로 적용한다 |
| `route_table` | `string`, 필수 | 이 서브넷을 연결할 `route_tables` 키. `aws_route_table_association`의 `route_table_id`가 된다 |
| `ipv6_index` | `number`, 선택, 기본 `null` | IPv6 /64 인덱스(`0`~`255`). `enable_ipv6 = true`일 때만 허용하며 `false`인데 값이 있으면 plan 실패(RSC-VPC-05). `null`이면 IPv6 CIDR을 할당하지 않는다 |
| `tags` | `map(string)`, 선택, 기본 `{}` | 이 서브넷에만 적용하는 커스텀 태그. EKS 컨트롤러 태그처럼 일부 서브넷에만 필요한 태그를 여기 둔다(13.2절) |

- AZ는 AZ ID(`apne2-az1`)로 받는다. AZ ID는 계정마다 다른 AZ 이름과 달리 물리 AZ를 가리키므로 계정 간 배치를 일관되게 한다. 예외는 AWS 리소스 인자가 AZ 이름만 받는 경우(VGW의 `availability_zone`)에 한하며, 그 필드는 AZ 이름을 받고 변수 설명에 AZ 이름임을 명시한다. 값 형식 검사는 RSC-AZ-01이다.
- 스택 서브넷에는 Role이나 계층 구분이 없다(2.2절). 모듈은 스택 서브넷의 `route_table` 값에 제약을 두지 않으며, `shared_public`과 `vpc_endpoint_subnets`만 각각 RSC-PUB-04, RSC-VPCE-07의 제약을 받는다.

---

## 3. 라우팅

- Route Table은 호출자가 `route_tables` 입력에 **명시적으로 선언**하고, 모든 서브넷 항목(Shared Public·VPC Endpoint 포함)은 `route_table` 필드로 Route Table 키를 적는다. 모듈은 모드나 규칙으로 Route Table을 도출하지 않고 스스로 만드는 Route Table도 없으며, 입력 파일만 읽어도 어느 서브넷이 어느 경로를 갖는지 드러나야 한다. Public Subnet용 IGW Route Table도 호출자가 선언한다.
- Route Table은 **목적지 → 대상 표**다. `routes`의 키는 목적지 CIDR(IPv4 또는 IPv6)이고 값은 대상 하나를 가리키는 객체다. 대상은 이 모듈이 만드는 게이트웨이(`gateway`: `igw`, `eigw`, `vgw`), `nat_gateways`의 키(`nat_gateway`), `eni_interfaces`의 키(`eni`), 호출자가 만든 ENI(`network_interface_id`) 중 정확히 하나다. 모듈이 만드는 대상은 키로, 호출자가 만든 대상은 ID로 가리킨다. 경로가 없는 Route Table은 `routes`를 비운다. `local` 경로는 AWS가 VPC CIDR과 보조 CIDR마다 자동으로 두므로 선언 대상이 아니다.
- IPv6 기본 경로(Egress-only IGW)는 호출자가 `routes`에 `::/0` 같은 IPv6 목적지로 직접 적으며 모듈이 IPv4 경로에서 도출하지 않는다. 생성 조건은 RSC-RT-05가 정의한다.
- 참조 방향 원칙은 [12.1절](#121-입력-변수-정의-규칙)을 따른다. 이 모듈에서는 서브넷이 Route Table을, 경로가 NAT나 ENI를, NAT와 ENI가 서브넷을 가리키며, 상위가 하위를 나열하는 예외는 DB·ElastiCache Subnet Group의 멤버뿐이다.
- Route Table과 NAT는 항상 Shared Network 리소스다. 스택 전용 Route Table이라는 개념은 두지 않으며 여러 스택의 서브넷이 같은 Route Table을 가리킬 수 있다. 반대로 한 스택만 가리키는 Route Table을 선언해 그 스택에만 경로를 두는 것도 가능하며, 같은 NAT를 참조하면 비용이 늘지 않는다. 어떤 서브넷도 가리키지 않는 Route Table도 선언된 대로 만든다(RSC-RT-03).
- Gateway Endpoint 연결은 `vpc_endpoints.gateway`가 정하고 모든 Route Table에 자동 적용된다(RSC-RT-06). VGW 경로 전파는 Route Table의 `propagate_vgw`로 켠다. VPC Peering·Transit Gateway 경로는 연결을 만드는 전용 모듈의 몫이며 이 모듈의 경로 대상에 두지 않는다(5.2절).
- Terraform Resource Address는 `for_each` 기반의 안정적인 Key를 사용해야 한다. 리소스별 키 체계는 6절이 정의한다.
- 경로 객체의 필드 제약, IPv6 경로, Association 등 리소스 수준 요구사항은 [REQUIREMENTS 6.7절](REQUIREMENTS.md#67-route-table-route-association)이 정의한다.

---

## 4. NAT

- NAT Gateway는 `nat_gateways` 입력에 선언한 만큼 만든다. 항목마다 NAT를 배치할 Shared Public Subnet을 `public_subnet`으로 적으며, 입력이 비어 있으면 NAT는 0개다. 여러 Route Table이 한 NAT를 참조할 수 있어, 경로만 다른 Route Table을 추가해도 NAT가 늘지 않는다.
- NAT는 Shared Network 리소스다(3절). 스택 전용 Public Subnet에는 배치하지 않는다.
- Production 권장 구성은 사용하는 AZ마다 NAT 1개이며, 각 서브넷은 같은 AZ의 NAT를 가리키는 Route Table에 연결한다. 이 구성에서는 한 AZ의 NAT 장애가 다른 AZ에 영향을 주지 않는다. 비용 최소 구성으로 NAT 1개를 여러 AZ가 공유할 수 있으나 Cross-AZ 데이터 전송 비용과 AZ 장애 영향이 따른다.
- NAT Gateway 대신 NAT 인스턴스·어플라이언스를 쓰는 구성도 지원한다. 그때는 `nat_gateways`를 비우고 Route Table의 기본 경로가 ENI를 가리킨다(3절). ENI는 `eni_interfaces` 입력으로 이 모듈이 서브넷에 만들거나([REQUIREMENTS 6.6절](REQUIREMENTS.md#66-network-interface-eni와-security-group)), 호출자가 만들어 ID를 넘긴다. 모듈이 만들면 인스턴스를 교체해도 경로 대상과 사설 IP, Security Group이 그대로 남는다. ENI에 붙일 SG도 `security_groups` 입력으로 모듈이 만들 수 있으며 룰은 호출자가 붙인다(5.1절). 인스턴스 자체(AMI, 인스턴스 타입, EIP)와 ENI를 인스턴스에 붙이는 일은 어느 경우든 이 모듈 범위 밖이다.
- NAT의 키·이름, `public_subnet` 제약, EIP 재사용, Cross-AZ 경고 표기 등 리소스 수준 요구사항은 [REQUIREMENTS 6.5절](REQUIREMENTS.md#65-nat-gateway와-eip)이 정의한다.

---

## 5. 공유 서비스와 외부 연결

### 5.1 Shared Service Private Access

- Toolchain, Observability 같은 Shared Service Stack은 `stack_subnets`의 스택으로 정의한다. 전용 서브넷을 가지며 같은 VPC의 다른 워크로드와 Private IP, Internal LB, Private DNS로 통신한다. Public IP나 Internet Gateway를 필수로 요구하지 않는다.
- 이 모듈의 구현 범위는 스택별 서브넷 격리, 라우팅, 스택 NACL 입력([REQUIREMENTS 6.8절](REQUIREMENTS.md#68-network-acl))까지다. 포트 수준의 접근 제어는 워크로드 모듈의 책임이며, 이 모듈은 접근 정책을 위한 별도 입력을 두지 않는다.
- 예외는 이 모듈이 만드는 ENI에 붙일 Security Group이다. `security_groups` 입력으로 SG와 그 인바운드·아웃바운드 룰을 선언형으로 만들며([REQUIREMENTS 6.6절](REQUIREMENTS.md#66-network-interface-eni와-security-group)), 룰은 인라인 블록이 아니라 독립 룰 리소스로 만들어 호출자가 같은 SG에 룰을 더해도 이 모듈의 plan이 흔들리지 않는다(RSC-SG-03). 모듈은 기본 룰 골격을 강제하지 않고 호출자가 적은 룰만 만든다. 워크로드 SG는 여전히 워크로드 모듈이 만들며, Endpoint 전용 SG(RSC-VPCE-04)는 모듈이 룰까지 정하는 또 다른 예외다.
- 호출자가 스택 NACL과 Security Group을 설계할 때 참고할 접근 정책 예시는 README의 "Shared Service 접근 정책 예시" 절에 둔다. 모듈 요구사항이 아니다.

### 5.2 VPC Peering

VPC Peering은 이 모듈 범위 밖이다. Peering 연결, 수락, Peering 경로는 별도 모듈 [tfmodule-aws-vpc-peer](https://github.com/oniops/tfmodule-aws-vpc-peer/blob/main/README.md)로 구성한다. 이 절이 Peering 관련 서술의 유일한 정의다.

- 이 모듈은 Peering 입력을 두지 않으며 Peering 리소스와 경로를 만들지 않는다.
- Peering 모듈이 필요로 하는 값은 이 모듈의 출력 `vpc_id`, `vpc_cidr_block`, `route_table_ids`(10절)로 전달한다. Peering 경로를 추가할 Route Table은 호출자가 `route_table_ids`에서 키로 골라 넘긴다.
- Peering 모듈이 이 모듈의 Route Table에 경로를 추가해도 이 모듈의 plan에 변경이 생기지 않아야 한다. 이를 위해 모든 경로는 `aws_route` 리소스로 만들고 `aws_route_table`의 인라인 `route` 블록을 쓰지 않는다(RSC-RT-02).
- Peering 대상 리전·계정, 개수, Transitive Routing 등의 제약은 Peering 모듈의 README를 따른다.

### 5.3 VPN Gateway

- 온프레미스 등 외부 네트워크와의 Site-to-Site VPN 연결을 위해 VGW 1개와 여러 Customer Gateway를 선언형 입력으로 지원해야 한다.
- VGW의 경로 전파는 각 Route Table의 `propagate_vgw`가 켠 Route Table에만 적용하며, VPN Connection 자체는 모듈 범위 밖이다. 리소스 수준 요구사항은 [REQUIREMENTS 6.11절](REQUIREMENTS.md#611-vpn-gateway와-customer-gateway)이다.

---

## 6. 리소스 키 체계

3절의 `for_each` 기반 안정 키를 모든 리소스에 확장한다. 키는 호출자가 입력에서 정한 이름으로만 구성하며 목록 순서·인덱스·AZ에서 파생하지 않는다. 서브넷·Route Table·NAT의 이름은 호출자가 정하고 모듈은 접두어와 유형 접미어만 붙인다(7절).

| 리소스 | 키 형식 | 예시 |
| --- | --- | --- |
| Shared Public Subnet | `shared-network/public/<name>` | `shared-network/public/pub-a1` |
| VPC Endpoint Subnet (선택) | `shared-network/vpce/<name>` | `shared-network/vpce/vpce-a1` |
| Stack Subnet (스택 전용 Public 포함) | `<stack>/<name>` | `web/app-a1`, `web/data-a1`, `web/web-pub-a1` |
| Route Table | `<rt_key>` (`route_tables` 키) | `pub`, `pri-a1` |
| NAT Gateway, EIP | `<nat_key>` (`nat_gateways`의 키) | `a1` |
| Network Interface | `<eni_key>` (`eni_interfaces`의 키) | `natsvc-a1` |
| Security Group | `<sg_key>` (`security_groups`의 키) | `nat-appliance` |
| Security Group Rule | `<sg_key>/<direction>/<rule_name>` | `nat-appliance/egress/https` |
| Route | `<rt_key>/<destination>` | `pri-a1/0.0.0.0/0` |
| Route Table Association | Subnet 키와 동일 | `web/app-a1` |
| Network ACL | `<stack>` 또는 `shared-network/public` | `web` |
| Network ACL Rule | `<nacl_key>/<direction>/<rule_name>` | `web/ingress/allow-app-tier` |
| VPC Endpoint | `<service>` (Gateway는 `s3`, `dynamodb`) | `ecr.api` |
| Gateway Endpoint RT 연결 | `<service>/<rt_key>` | `s3/pri-a1` |
| Flow Log | `<flow_log_key>` (`flow_logs`의 키) | `s3`, `cloudwatch` |
| Customer Gateway | `<cgw_key>` | `hq-fw-1` |
| VGW Route Propagation | `<rt_key>` (`propagate_vgw = true`인 Route Table의 키) | `pri-a1` |
| VGW Attachment (`vpn_gateway.existing_id` 지정 시) | 단일 | — |
| Secondary CIDR | `<cidr>` | `100.64.0.0/16` |
| DB Subnet Group | `<db_subnet_group>` (스택 `db_subnet_group`의 키) | `data` |
| ElastiCache Subnet Group | `<elasticache_subnet_group>` (스택 `elasticache_subnet_group`의 키) | `data` |
| Redshift Subnet Group | `<redshift_subnet_group>` (스택 `redshift_subnet_group`의 키) | `data` |
| MemoryDB Subnet Group | `<memorydb_subnet_group>` (스택 `memorydb_subnet_group`의 키) | `data` |

---

## 7. 이름 규칙

이름 접두어 `<prefix>`는 필수 입력 `context.name_prefix`로 한다(11절). 모든 리소스의 이름은 `<prefix>-<이름>-<유형 접미어>`이며, `<이름>`은 호출자가 정한 마지막 마디(리소스 키의 마지막 세그먼트)이지 `/`를 포함한 리소스 키 전체가 아니다. 이름이 없는 단일 리소스는 `<prefix>-<유형 접미어>`다. 그 이름이 `Name` 태그인지 리소스 `name` 인자인지는 표의 적용 대상 열이 정한다. 모듈은 스택·AZ를 조합해 이름을 만들어 내지 않는다. 예를 들어 `name_prefix = "dxplat-an2p"`, 서브넷 이름 `blb-a1`이면 서브넷은 `dxplat-an2p-blb-a1-sn`이고, Route Table 키 `pri-a1`이면 Route Table은 `dxplat-an2p-pri-a1-rt`, NAT 키 `a1`이면 NAT는 `dxplat-an2p-a1-nat`이다. 이 표가 이름 규칙의 유일한 정의다.

| 리소스 | 이름 | 이름 출처 | 적용 대상 |
| --- | --- | --- | --- |
| VPC | `<prefix>-vpc` | 없음 | `Name` 태그 |
| Internet Gateway | `<prefix>-igw` | 없음 | `Name` 태그 |
| Egress-only IGW | `<prefix>-eigw` | 없음 | `Name` 태그 |
| Subnet (Shared, Stack 모두) | `<prefix>-<name>-sn` | 서브넷 이름(리소스 키의 마지막 마디) | `Name` 태그 |
| Route Table | `<prefix>-<rt_key>-rt` | `route_tables` 키 | `Name` 태그 |
| NAT Gateway | `<prefix>-<nat_key>-nat` | `nat_gateways` 키 | `Name` 태그 |
| EIP | `<prefix>-<nat_key>-eip` | `nat_gateways` 키 | `Name` 태그 |
| Network Interface | `<prefix>-<eni_key>-eni` | `eni_interfaces` 키 | `Name` 태그 |
| Security Group | `<prefix>-<sg_key>-sg` | `security_groups` 키 | 리소스 `name` 인자와 `Name` 태그 |
| Network ACL | `<prefix>-<stack>-nacl`, Shared Public은 `<prefix>-shared-public-nacl` | 스택 키 / Shared Public은 고정값 `shared-public` | `Name` 태그 |
| 기본 SG / RT / NACL | `<prefix>-default-sg`, `<prefix>-default-rt`, `<prefix>-default-nacl` | 없음 | `Name` 태그 |
| DB Subnet Group | `<prefix>-<db_subnet_group>-sng` | 스택 `db_subnet_group`의 키 | 리소스 `name` 인자와 `Name` 태그 |
| ElastiCache Subnet Group | `<prefix>-<elasticache_subnet_group>-ecsng` | 스택 `elasticache_subnet_group`의 키 | 리소스 `name` 인자와 `Name` 태그 |
| Redshift Subnet Group | `<prefix>-<redshift_subnet_group>-rssng` | 스택 `redshift_subnet_group`의 키 | 리소스 `name` 인자와 `Name` 태그 |
| MemoryDB Subnet Group | `<prefix>-<memorydb_subnet_group>-mdsng` | 스택 `memorydb_subnet_group`의 키 | 리소스 `name` 인자와 `Name` 태그 |
| VPC Endpoint | `<prefix>-<service>-vpce` | 서비스 이름 | `Name` 태그 |
| Endpoint SG | `<prefix>-vpce-sg` | 없음 | 리소스 `name` 인자와 `Name` 태그 |
| VGW / CGW | `<prefix>-vgw`, `<prefix>-<cgw_key>-cgw` | 없음 / `customer_gateways` 키 | `Name` 태그 |
| VGW Attachment | 해당 없음(태그를 지원하지 않는 리소스) | 없음 | 해당 없음 |
| Flow Log | `<prefix>-<flow_log_key>-vpc-flow` | `flow_logs` 키 | `Name` 태그 |
| Private Hosted Zone | 도메인 이름 | 없음 | 리소스 `name` 인자와 `Name` 태그 |
| DHCP Options | `<prefix>-dhcp` | 없음 | `Name` 태그 |

- 서브넷 이름은 VPC 전체(Shared와 모든 스택)에서 유일해야 한다. 같은 이름이 두 곳에 있으면 `Name` 태그가 겹치므로 plan 실패.
- 호출자가 정하는 이름 키(스택, 서브넷, Route Table, NAT, ENI, Security Group, NACL 룰, CGW, 네 종류의 Subnet Group, Flow Log 목적지)에는 소문자, 숫자, `-`만 허용한다. 위반 시 plan 실패. AWS 서비스 이름(`ecr.api`)과 CIDR처럼 AWS 값 자체가 키인 경우는 이 규칙의 대상이 아니다.
- `Name`을 갖지 않는 리소스: NACL 룰, Security Group 룰, VGW Attachment. 이름 규칙 표의 대상이 아니며 태그는 상위 리소스의 태그를 따른다([REQUIREMENTS 7.3.1절](REQUIREMENTS.md#731-각-태그-입력이-적용되는-리소스)).
- 적용 대상이 리소스 `name` 인자인 리소스는 `<prefix>`와 합친 최종 이름이 AWS의 문자·길이 제약을 받는다. 가장 짧은 제약은 IAM 롤 64자이며 나머지는 255자 이상이다. 모듈은 최종 이름의 길이를 검사하지 않고 호출자가 `context.name_prefix` 길이로 관리하며, 이 사실을 변수 `description`에 적는다. 이름 키의 문자 규칙은 위 항목이 정한다.
- 예약 키. 호출자가 정하는 이름 키 중 다음은 쓸 수 없으며 위반 시 plan 실패다. 스택 키가 `shared-`로 시작하는 것(Shared 리소스의 키 접두어 `shared-network/`와 이름 `<prefix>-shared-public-nacl`이 `shared-`를 쓴다), Security Group 키 `vpce`(Endpoint 전용 SG 이름 `<prefix>-vpce-sg`와 겹친다, RSC-VPCE-04). 이 항목이 예약 키의 유일한 정의다.

---

## 8. 입력 계약

### 8.1 입력 변수

11절 입력 모델을 리소스별로 구체화한다. 이 표가 모듈 입력의 유일한 정의다. 복잡한 변환을 `locals`에서 하지 않고 입력 구조 자체가 리소스 인자에 그대로 대응되어야 한다. 모든 행은 선택 필드를 `optional(<타입>, <기본값>)`으로 적어 필수·선택과 기본값이 표에서 바로 읽히게 한다. 표에서 쓰는 약칭 `서브넷Map`·`NACL`·`NACL_RULE`·`SG_RULE`의 타입 정의는 8.2절에 둔다.

| 입력 | 타입 골격 | 대응 절 |
| --- | --- | --- |
| `context` | `object({ name_prefix = string, tags = map(string), region = string, pri_domain = string, region_alias = optional(string), project = optional(string), environment = optional(string), env_alias = optional(string), owner = optional(string), team = optional(string), cost_center = optional(number) })`, 필수. 11절 참조 버전 출력 `context`의 부분집합이며 출력에만 있는 필드는 타입에 두지 않는다. 필수 필드도 값이 `null`일 수 있다(11절) | 7절, [REQUIREMENTS 7.3.1절](REQUIREMENTS.md#731-각-태그-입력이-적용되는-리소스), 11절 |
| `vpc_cidr`, `secondary_cidrs` | `string`(필수), `set(string)` 기본 `[]` | [REQUIREMENTS 6.1절](REQUIREMENTS.md#61-vpc-본체) |
| `enable_ipv6` | `bool`, 기본 `false` | RSC-VPC-05 |
| `shared_public` | `object({ tags = optional(map(string), {}), subnets = 서브넷Map, nacl = optional(NACL, null) })`, 기본 `null` | [REQUIREMENTS 6.3절](REQUIREMENTS.md#63-shared-public-network-public-subnet-internet-gateway), [REQUIREMENTS 6.8절](REQUIREMENTS.md#68-network-acl) |
| `vpc_endpoint_subnets` | `서브넷Map`, 기본 `{}` | RSC-VPCE-07 |
| `route_tables` | `map(object({ routes = optional(map(object({ gateway = optional(string), nat_gateway = optional(string), eni = optional(string), network_interface_id = optional(string) })), {}), propagate_vgw = optional(bool, false), tags = optional(map(string), {}) }))`, 기본 `{}`. `routes`의 키는 목적지 CIDR | [REQUIREMENTS 6.7절](REQUIREMENTS.md#67-route-table-route-association) |
| `nat_gateways` | `map(object({ public_subnet = string, eip_allocation_id = optional(string), tags = optional(map(string), {}) }))`, 기본 `{}` | [REQUIREMENTS 6.5절](REQUIREMENTS.md#65-nat-gateway와-eip) |
| `security_groups` | `map(object({ description = optional(string), ingress = optional(map(SG_RULE), {}), egress = optional(map(SG_RULE), {}), tags = optional(map(string), {}) }))`, 기본 `{}`. 키는 SG 이름, `ingress`·`egress`의 키는 룰 이름이다 | [REQUIREMENTS 6.6절](REQUIREMENTS.md#66-network-interface-eni와-security-group) |
| `eni_interfaces` | `map(object({ subnet = string, private_ips = optional(set(string)), security_group_names = optional(set(string), []), security_group_ids = optional(set(string), []), source_dest_check = optional(bool, true), interface_type = optional(string), description = optional(string), tags = optional(map(string), {}) }))`, 기본 `{}`. 키는 ENI 이름, `subnet`은 서브넷 이름, `security_group_names`는 `security_groups`의 키다 | [REQUIREMENTS 6.6절](REQUIREMENTS.md#66-network-interface-eni와-security-group) |
| `stack_subnets` | `map(object({ tags = optional(map(string), {}), subnets = 서브넷Map, nacl = optional(NACL, null), db_subnet_group = optional(map(set(string)), {}), elasticache_subnet_group = optional(map(set(string)), {}), redshift_subnet_group = optional(map(set(string)), {}), memorydb_subnet_group = optional(map(set(string)), {}) }))`, 기본 `{}`. `subnets`의 키는 서브넷 이름이며 Role 계층이 없다. 네 Subnet Group 필드의 키는 그룹 이름이고 값은 서브넷 이름 집합 | [REQUIREMENTS 6.4절](REQUIREMENTS.md#64-workload-stack-subnet-set), [REQUIREMENTS 6.8절](REQUIREMENTS.md#68-network-acl) |
| `vpc_endpoints` | `object({ gateway = optional(set(string), []), interface = optional(map(object({ private_dns_enabled = optional(bool, true), policy = optional(string), security_group_names = optional(set(string), []), security_group_ids = optional(set(string), []) })), {}) })`, 기본 `{}`, `nullable = false`. 두 필드가 모두 비어 있는 `{}`와 `null`은 뜻이 같아(리소스 0개) 명시적 `null`도 기본값으로 대체된다(DEC-104) | [REQUIREMENTS 6.10절](REQUIREMENTS.md#610-vpc-endpoints) |
| `vpn_gateway` | `object({ amazon_side_asn = optional(string), availability_zone = optional(string), existing_id = optional(string) })`, 기본 `null`. `{}`를 주면 AWS 기본 ASN으로 VGW 1개 | [REQUIREMENTS 6.11절](REQUIREMENTS.md#611-vpn-gateway와-customer-gateway) |
| `customer_gateways` | `map(object({ bgp_asn = string, ip_address = string, device_name = optional(string), tags = optional(map(string), {}) }))`, 기본 `{}` | [REQUIREMENTS 6.11절](REQUIREMENTS.md#611-vpn-gateway와-customer-gateway) |
| `flow_logs` | `map(object({ log_destination_arn = string, log_destination_type = string, iam_role_arn = optional(string), traffic_type = optional(string, "ALL"), max_aggregation_interval = optional(number, 600), log_format = optional(string, <29필드 기본 포맷>), destination_options = optional(object({ file_format = optional(string, "parquet"), hive_compatible_partitions = optional(bool, true), per_hour_partition = optional(bool, true) })) }))`, 기본 `{}`. 키는 목적지 이름이며 항목 하나가 Flow Log 하나다. 빈 Map 이 0개를 뜻하는 `nat_gateways` 와 같은 관례이며, 목적지를 한 겹 더 감싸던 `flow_log = { destinations = ... }` 를 대체한다(DEC-105) | [REQUIREMENTS 6.12절](REQUIREMENTS.md#612-vpc-flow-logs) |
| `private_dns` | `object({ domain_name = optional(string), additional_vpc_ids = optional(set(string), []) })`, 기본 `null`. `{}`를 주면 `context.pri_domain`으로 존 1개 | [REQUIREMENTS 6.13절](REQUIREMENTS.md#613-private-dns-route53-private-hosted-zone) |
| `dhcp_options` | `object({ domain_name = optional(string), domain_name_servers = optional(list(string), ["AmazonProvidedDNS"]), ntp_servers = optional(list(string), []), netbios_name_servers = optional(list(string), []), netbios_node_type = optional(string) })`, 기본 `null`. `{}`를 주면 `context.pri_domain`과 기본 DNS로 옵션 세트 1개 | [REQUIREMENTS 6.9절](REQUIREMENTS.md#69-기본-리소스-관리-default-sg-rt-nacl-dhcp) |
| `tags` | `map(string)`, 기본 `{}`. 모든 리소스에 적용하는 모듈 공통 커스텀 태그([REQUIREMENTS 7.3절](REQUIREMENTS.md#73-태그-정책) 2단계) | [REQUIREMENTS 7.3.1절](REQUIREMENTS.md#731-각-태그-입력이-적용되는-리소스) |

- 모든 `object` 입력은 `optional()`로 선택 필드를 표현한다. 정적 기본값과 파생 기본값의 처리는 [12.1절](#121-입력-변수-정의-규칙)을 따르며, 파생 규칙(`context.pri_domain`, AWS 기본값 적용 등)은 본문 요구사항 ID와 변수 `description`에 명시한다.
- 스칼라 타입은 대응하는 AWS provider 인자 타입을 따른다. `netbios_node_type`, `bgp_asn`, `amazon_side_asn`은 provider 스키마에서 문자열이므로 `string`으로 받는다(provider 6.64.0 기준).
- 이 표에 없는 입력은 두지 않는다. 입력을 추가할 때는 이 표와 대응 절을 같은 변경에서 갱신한다.

### 8.2 타입 약칭

8.1절 입력 표가 쓰는 약칭의 타입 정의다.

```hcl
# 서브넷Map (2.3절)
map(object({
  az          = string
  cidr        = string
  route_table = string
  ipv6_index  = optional(number)
  tags        = optional(map(string), {})
}))

# NACL (REQUIREMENTS 6.8절). ingress·egress 는 룰 이름을 키로 하는 Map 이다
object({
  ingress = optional(map(NACL_RULE), {})
  egress  = optional(map(NACL_RULE), {})
})

# SG_RULE (RSC-SG-04). ingress·egress 는 룰 이름을 키로 하는 Map 이다.
# icmp·icmpv6 는 from_port 가 ICMP 타입, to_port 가 코드다(전체는 -1).
object({
  ip_protocol                    = string
  from_port                      = optional(number)
  to_port                        = optional(number)
  cidr_ipv4                      = optional(string)
  cidr_ipv6                      = optional(string)
  prefix_list_id                 = optional(string)
  referenced_security_group_name = optional(string)
  referenced_security_group_id   = optional(string)
  description                    = optional(string)
})

# NACL_RULE (RSC-NACL-02)
object({
  rule_number     = number
  rule_action     = string
  protocol        = string
  from_port       = optional(number)
  to_port         = optional(number)
  cidr_block      = optional(string)
  ipv6_cidr_block = optional(string)
  icmp_type       = optional(number)
  icmp_code       = optional(number)
})
```

### 8.3 프로토콜과 포트 공통 규칙

NACL 룰(RSC-NACL-02)과 Security Group 룰(RSC-SG-04)이 함께 쓰는 규칙이다. 이 절이 유일한 정의이며 두 요구사항은 여기를 참조하고 다시 적지 않는다. 필드 이름은 리소스 인자를 따라 NACL 룰은 `protocol`, SG 룰은 `ip_protocol`이다.

- 프로토콜 값은 `"-1"`(전체), `"tcp"`, `"udp"`, `"icmp"`, `"icmpv6"`와 각각에 대응하는 번호 문자열 `"6"`, `"17"`, `"1"`, `"58"`만 허용한다. 허용 값 밖이면 plan 실패.
- `"tcp"`·`"udp"`는 `from_port`·`to_port`가 필수다. 없으면 plan 실패.
- `"-1"`은 포트를 갖지 않는다. 포트나 ICMP 필드를 주면 plan 실패.
- ICMP의 타입·코드를 담는 자리는 리소스마다 다르다. NACL 룰은 전용 필드 `icmp_type`·`icmp_code`에, SG 룰은 포트 자리에 담아 `from_port`가 타입, `to_port`가 코드이며 전체를 뜻할 때 `-1`을 적는다. 어느 쪽이든 값이 없으면 plan 실패.

---

## 9. 입력 검증과 검사 배치

REQUIREMENTS 7·6절이 요구하는 검증이 코드 어디에 놓이는지 정의한다. 9.1절이 원칙을, 9.2절이 검사 하나하나의 배치를, 9.3절이 변수 `description`에 적어야 하는 내용을 정한다.

### 9.1 검증 원칙

- 입력 조합이 유효하지 않으면 `plan` 단계에서 `validation` 또는 `precondition`으로 실패해야 한다. 조건 미달을 이유로 리소스를 조용히 0개 만들지 않는다. 이 절은 검증 원칙을 정하고, 검사 하나하나를 둘 곳(`validation`인지 `precondition`인지, `precondition`이면 어느 리소스인지)은 9.2절 표가 정의한다.
- `vpc_cidr`, `secondary_cidrs`, 모든 서브넷의 `cidr`은 IPv4 CIDR 형식이어야 한다. 형식 검사는 포함·겹침 검사보다 **먼저** 끝나야 한다. 포함·겹침 검사가 `locals`에서 CIDR을 정수로 바꾸는 동안(1.5.7에는 `cidrcontains`가 없다) 형식이 깨진 값이 섞이면 `locals` 평가가 `precondition`보다 먼저 실패해 요구사항이 정한 메시지 대신 Terraform 내부 오류가 나온다. 그래서 형식 검사만 `validation`(V-25)에 두고 포함·겹침은 `precondition`(P-02)에 둔다. 9.2.2절 마지막 불릿과 같은 원칙이다.
- 모든 서브넷의 CIDR은 VPC CIDR 또는 보조 CIDR 안에 있어야 하고 서로 겹치지 않아야 한다. 위반 시 plan 실패. 검사 대상은 서브넷 CIDR 사이의 관계이며, `secondary_cidrs` 항목이 `vpc_cidr`이나 다른 보조 CIDR과 겹치는지는 검사하지 않는다. AWS가 `aws_vpc_ipv4_cidr_block_association` 생성에서 거부하기 때문이다(RSC-ENI-03과 같은 원칙).
- 입력이 다른 입력의 키를 참조하는 경우(서브넷의 `route_table`, 경로의 `nat_gateway`·`eni`, NAT의 `public_subnet`, ENI의 `subnet`·`security_group_names`, 네 종류 Subnet Group의 멤버) 참조 대상 키가 존재하지 않으면 plan 실패.
- Route Table 입력을 참조하는 검사(RSC-PUB-04, RSC-VPCE-07, 서브넷의 `route_table` 참조)는 `aws_route_table_association`과 `aws_route`의 `precondition`에 둔다(배경은 DEC-071). 경로 객체 안에서 끝나는 대상 택일 검사는 `route_tables`의 `validation`이다(9.2.1절). 검사 대상 값이 apply 전에 확정되지 않으면 그 검사는 apply 시점으로 미뤄진다.
- 파생 기본값 원칙은 [12.1절](#121-입력-변수-정의-규칙)을 따른다. 이 모듈에서는 `domain_name` 생략 시 `context.pri_domain`이 그 사례이며, 파생 원본이 `null`이면 plan 실패다(RSC-DEF-04, RSC-DNS-01).

[12절 코드 컨벤션](#12-코드-컨벤션)에서 이어지는 규칙은 다음과 같다.

- 허용 값이 정해진 입력은 `validation` 블록으로 검사한다.
- 입력 조합이 유효하지 않으면 `validation` 또는 `precondition` 으로 plan 단계에서 실패시킨다. 조건 미달을 이유로 리소스를 조용히 0개 만들지 않는다.
- 한 변수 안에서 끝나는 검사는 `validation` 에, 다른 입력을 함께 봐야 하는 검사(참조 대상 존재, 입력 간 조합)는 `precondition` 에 둔다.
- `precondition` 을 어느 리소스에 둘지는 참조 방향을 보고 정하며, 참조 관계상 나중에 오는 리소스에 둔다. 이 모듈의 검사별 구현 위치는 9.1절과 9.2절이 정의한다.

### 9.2 검사 배치

9.1절의 검증 원칙을 입력별로 구체화한다. 이 절이 각 검사를 `validation`과 `precondition` 중 어디에 두는지, `precondition`이면 어느 리소스에 두는지의 유일한 정의다. 본문에 검사를 추가하거나 바꾸면 같은 변경에서 아래 두 표를 함께 갱신한다. 실패 케이스 테스트는 이 두 표를 그대로 따른다([REQUIREMENTS 8.6절](REQUIREMENTS.md#86-실패-케이스)).

분류 기준은 하나다. `variable`의 `validation`은 **자기 변수 하나만** 참조할 수 있다. 다른 변수를 참조하는 `validation`은 Terraform 1.9 이상 기능이고 이 모듈의 `required_version` 하한은 `1.5.7`이므로([REQUIREMENTS 8.3절](REQUIREMENTS.md#83-terraform-버전)), 두 개 이상의 입력을 함께 봐야 하는 검사는 예외 없이 `precondition`에 둔다. 반대로 한 변수 안에서 끝나는 검사는 그 변수의 항목 여러 개를 서로 비교하는 검사(Map 키 간 중복 등)라도 `validation`이다.

#### 9.2.1 한 변수 안에서 끝나는 검사 (`validation`)

| ID | 검사 항목 | 대상 변수 | 근거 |
| --- | --- | --- | --- |
| V-01 | 경로 대상 `gateway`가 `igw`·`eigw`·`vgw` 중 하나 | `route_tables` | RSC-RT-01 |
| V-02 | 경로 객체의 네 대상 필드 택일, `network_interface_id`의 `eni-` 형식 | `route_tables` | RSC-RT-01 |
| V-03 | `gateway = "eigw"`인데 목적지가 IPv4 | `route_tables` | RSC-RT-01 |
| V-04 | `flow_logs`의 키 문자 규칙과 항목별 `log_destination_type`·`traffic_type`·`max_aggregation_interval` 허용 값 | `flow_logs` | RSC-FLOW-02, RSC-FLOW-04, 7절 |
| V-05 | `destination_options`가 `s3` 목적지에만 있고 `file_format`이 허용 값 | `flow_logs` | RSC-FLOW-05 |
| V-06 | `vpc_endpoints.gateway`가 `s3`·`dynamodb` | `vpc_endpoints` | RSC-VPCE-01 |
| V-07 | `dhcp_options.netbios_node_type`이 `"1"`·`"2"`·`"4"`·`"8"` | `dhcp_options` | RSC-DEF-04 |
| V-08 | `eni_interfaces.<key>.interface_type`이 `efa`·`efa-only` 중 하나이거나 `null` | `eni_interfaces` | RSC-ENI-06 |
| V-09 | `security_groups`에 예약 키 `vpce` | `security_groups` | RSC-SG-02 |
| V-10 | SG 룰 소스 다섯 필드 택일, 8.3절 프로토콜·포트 규칙 | `security_groups` | RSC-SG-04, 8.3절 |
| V-11 | SG 룰의 `referenced_security_group_name`이 `security_groups`에 존재 | `security_groups` | RSC-SG-04 |
| V-12 | `existing_id`와 `amazon_side_asn`·`availability_zone` 동시 지정 | `vpn_gateway` | RSC-VPN-02 |
| V-13 | 서브넷 `az`가 AZ ID 형식(`-az<번호>`로 끝남) | `shared_public`, `vpc_endpoint_subnets`, `stack_subnets` | RSC-AZ-01 |
| V-14 | 서브넷 `ipv6_index` 범위(`0`~`255`) | `shared_public`, `vpc_endpoint_subnets`, `stack_subnets` | RSC-VPC-05 |
| V-15 | 이름 키 문자 규칙(소문자·숫자·`-`) | `route_tables`, `nat_gateways`, `eni_interfaces`, `security_groups`, `customer_gateways`, `shared_public`, `vpc_endpoint_subnets`, `stack_subnets` | 7절 |
| V-16 | 스택 키가 `shared-`로 시작 | `stack_subnets` | 7절 |
| V-17 | 스택 `subnets`가 비어 있음 | `stack_subnets` | RSC-SUB-10 |
| V-18 | `shared_public`을 지정했는데 `subnets`가 비어 있음 | `shared_public` | RSC-PUB-01 |
| V-19 | `vpc_endpoint_subnets`에 같은 `az` 값을 가진 서브넷이 2개 이상 | `vpc_endpoint_subnets` | RSC-VPCE-07 |
| V-20 | 네 Subnet Group의 멤버가 같은 스택의 서브넷, 멤버 수(DB는 2개 AZ 이상, 나머지 셋은 1개 이상), 같은 유형 안에서 스택 간 그룹 이름 중복 | `stack_subnets` | RSC-SUB-05·09·11·12·13 |
| V-21 | NACL 룰 `rule_action` 허용 값, `rule_number` 범위(`1`~`32766`), `cidr_block`·`ipv6_cidr_block` 택일, 8.3절 프로토콜·포트 규칙 | `shared_public`, `stack_subnets` | RSC-NACL-02, 8.3절 |
| V-22 | 같은 NACL·방향의 `rule_number` 중복 | `shared_public`, `stack_subnets` | RSC-NACL-03 |
| V-23 | `ipv6_cidr_block` 값이 IPv6 CIDR 형식 또는 예약 값 `vpc` | `shared_public`, `stack_subnets` | RSC-NACL-06 |
| V-24 | 보호 키 `Name` 포함 | `tags`, 그리고 `tags` 필드를 가진 모든 입력 | [REQUIREMENTS 7.3절](REQUIREMENTS.md#73-태그-정책) |
| V-25 | CIDR 값이 IPv4 CIDR 형식(`can(cidrhost(x, 0))`이고 `:`를 포함하지 않음) | `vpc_cidr`, `secondary_cidrs`, `shared_public`, `vpc_endpoint_subnets`, `stack_subnets` | 9.1절 |
| V-27 | `cloud-watch-logs` 목적지에 `iam_role_arn`이 없거나 `s3` 목적지에 `iam_role_arn`이 있음 | `flow_logs` | RSC-FLOW-03 |
| V-28 | `context.name_prefix`·`context.tags`가 `null` | `context` | 11절 |
| V-29 | 경로 목적지 키가 IPv4 또는 IPv6 CIDR 형식 | `route_tables` | RSC-RT-01 |
| V-30 | `eip_allocation_id`가 `eipalloc-` 형식 | `nat_gateways` | RSC-NAT-03 |
| V-31 | `security_group_ids` 항목이 `sg-` 형식 | `eni_interfaces` | RSC-ENI-05 |
| V-32 | `interface.<service>.security_group_ids` 항목이 `sg-` 형식 | `vpc_endpoints` | RSC-VPCE-02 |
| V-33 | `existing_id`가 `vgw-` 형식 | `vpn_gateway` | RSC-VPN-02 |
| V-34 | `additional_vpc_ids` 항목이 `vpc-` 형식 | `private_dns` | RSC-DNS-01 |
| V-35 | SG 룰의 `referenced_security_group_id`가 `sg-` 형식 | `security_groups` | RSC-SG-04 |

- V-28~V-35 는 DEC-102 가 더한 행이다. 이 가운데 V-30~V-35 여섯 행은 외부 리소스 식별자를 엉뚱한 값(모듈 키, IP 주소, 다른 유형의 ID)으로 적어도 plan 이 통과하고 apply 에서만 AWS 가 거부하던 자리를 막는다. V-29 는 목적지 키가 `destination_cidr_block`·`destination_ipv6_cidr_block` 중 어디로 들어갈지를 정하므로 형식이 깨지면 경로가 조용히 잘못 만들어진다.
- 한 행을 `validation` 블록 하나로 구현할 필요는 없다. NACL 룰(V-21·V-23)과 SG 룰(V-10·V-11)은 `error_message` 가 어느 룰이 왜 걸렸는지 말할 수 있도록 블록을 셋·둘로 나눠 구현한다. 반대로 한 블록이 여러 행을 함께 검사하는 것도 허용한다(V-15 의 이름 키 문자 규칙은 각 변수의 키 검사 블록에 들어 있다).
- `error_message` 는 검사에 걸린 **키**를 함께 낸다. 서브넷·룰·그룹·경로처럼 항목이 많은 입력은 이름만으로는 어디를 고칠지 알 수 없기 때문이다. `error_message` 는 조건이 참일 때도 평가되므로 그 안의 식도 `null` 안전해야 한다. `x != null && f(x)` 는 Terraform 이 단락 평가를 하지 않아 실패하므로 `x == null ? false : f(x)` 조건식으로 쓴다(DEC-093 (2), DEC-102).

#### 9.2.2 두 개 이상의 입력을 함께 보는 검사 (`precondition`)

| ID | 검사 항목 | 두는 리소스 | 근거 |
| --- | --- | --- | --- |
| P-01 | 서브넷 이름이 VPC 전체(Shared와 모든 스택)에서 유일 | `aws_vpc` | 7절 |
| P-02 | 서브넷 CIDR이 `vpc_cidr` 또는 `secondary_cidrs` 안에 있고 서로 겹치지 않음 | `aws_vpc` | 9.1절 |
| P-03 | 모든 서브넷의 `az`를 합쳐 서로 다른 AZ ID가 2개 이상 | `aws_vpc` | RSC-AZ-02 |
| P-04 | `ipv6_index`가 VPC 안에서 중복되지 않음 | `aws_vpc` | RSC-VPC-05 |
| P-05 | `enable_ipv6 = false`인데 `ipv6_index`가 `null`이 아닌 서브넷 | `aws_vpc` | RSC-VPC-05 |
| P-06 | `enable_ipv6 = false`인데 `ipv6_cidr_block`을 가진 NACL 룰 | `aws_network_acl_rule` | RSC-NACL-05 |
| P-07 | 서브넷의 `route_table`이 `route_tables`에 존재 | `aws_route_table_association` | 9.1절 |
| P-08 | `shared_public.subnets`가 `gateway = "igw"`인 `0.0.0.0/0` 경로를 가진 RT를 가리킴 | `aws_route_table_association` | RSC-PUB-04 |
| P-09 | `vpc_endpoint_subnets`가 기본 경로(`0.0.0.0/0`, `::/0`)가 없는 RT를 가리킴 | `aws_route_table_association` | RSC-VPCE-07 |
| P-10 | 경로의 `nat_gateway`가 `nat_gateways`에 존재 | `aws_route` | 9.1절 |
| P-11 | 경로의 `eni`가 `eni_interfaces`에 존재 | `aws_route` | 9.1절, RSC-ENI-07 |
| P-12 | 목적지가 `vpc_cidr`이나 `secondary_cidrs`와 같음 | `aws_route` | RSC-RT-01 |
| P-13 | `gateway = "vgw"`인데 `vpn_gateway`가 `null` | `aws_route` | RSC-RT-01 |
| P-14 | IPv6 목적지이거나 `gateway = "eigw"`인데 `enable_ipv6 = false` | `aws_route` | RSC-RT-01 |
| P-15 | `propagate_vgw = true`인데 `vpn_gateway`가 `null` | `aws_vpn_gateway_route_propagation` | RSC-RT-01, RSC-RT-11 |
| P-16 | NAT의 `public_subnet`이 `shared_public.subnets`에 존재(스택 서브넷 불가) | `aws_nat_gateway` | RSC-NAT-02 |
| P-17 | ENI의 `subnet`이 이 모듈이 만드는 서브넷에 존재 | `aws_network_interface` | RSC-ENI-02 |
| P-18 | ENI의 `security_group_names`가 `security_groups`에 존재 | `aws_network_interface` | RSC-ENI-05 |
| P-19 | `vpc_endpoints.interface`가 비어 있지 않은데 `vpc_endpoint_subnets`가 비어 있음 | `aws_vpc_endpoint` | RSC-VPCE-03 |
| P-20 | Endpoint를 만드는데 `context.region`이 `null` | `aws_vpc_endpoint`(Gateway·Interface 양쪽) | RSC-VPCE-01, RSC-VPCE-02 |
| P-21 | `domain_name` 생략 시 `context.pri_domain`이 `null` | `aws_vpc_dhcp_options` | RSC-DEF-04 |
| P-22 | `domain_name` 생략 시 `context.pri_domain`이 `null` | `aws_route53_zone` | RSC-DNS-01 |
| P-23 | Interface Endpoint의 `security_group_names`가 `security_groups`에 존재 | `aws_vpc_endpoint` | RSC-VPCE-02 |

- `precondition`을 둘 리소스는 참조 방향으로 정한다. Route Table 입력을 참조하는 검사를 `aws_subnet`에 두면 경로가 호출자 ENI를 가리키는 구성에서 순환 참조가 생기므로 `aws_route_table_association`과 `aws_route`에 둔다(9.1절).
- 입력만 보는 VPC 전역 검사(서브넷 이름 유일, CIDR, AZ, IPv6 인덱스)는 단일 리소스인 `aws_vpc`에 모아 한 번만 평가한다. `aws_subnet`에 두면 서브넷마다 같은 전역 검사가 반복된다.
- 검사 대상 값이 apply 전에 확정되지 않으면(호출자 ENI ID 등) 그 검사는 apply 시점으로 미뤄진다(9.1절).
- `context`의 `null`일 수 있는 필드(`region`, `pri_domain`)를 쓰는 리소스를 추가하면 그 리소스의 `precondition` 행을 같은 변경에서 더한다. 필드를 쓰는 리소스가 하나 늘었는데 행이 따라오지 않으면 그 리소스에서만 요구사항 메시지 대신 Terraform 내부 오류(문자열 보간의 `null`)가 나온다. P-20이 Gateway Endpoint를 빠뜨려 그 상태였다.
- 리소스 인자가 다른 리소스를 키로 조회하는 값(ENI·Interface Endpoint의 `security_group_names` → `aws_security_group`)은 `locals`에서 **존재하는 키만 남겨** 조회하고, 키 존재 검사는 그 리소스의 `precondition`에 둔다. 걸러내지 않으면 `locals` 평가가 `precondition`보다 먼저 실패해 요구사항이 정한 메시지 대신 Terraform 내부 오류(`Invalid index`)만 나온다.

### 9.3 변수 `description` 에 적을 내용

본문이 "변수 설명에 명시한다" 로 요구한 항목을 한곳에 모은다. 이 표가 그 목록의 유일한 정의이며, 본문에 그런 요구를 더하면 같은 변경에서 이 표에도 행을 더한다. **plan 노출** 열이 "아니오" 인 항목은 입력이 잘못돼도 plan 이 성공하므로 `description` 이 유일한 방어선이다.

| 변수 | 적을 내용 | 근거 | plan 노출 |
| --- | --- | --- | --- |
| `eni_interfaces` | `source_dest_check` 기본값은 `true`이며 NAT·방화벽 어플라이언스용 ENI는 `false`로 줘야 전달 트래픽이 버려지지 않는다 | RSC-ENI-04 | 아니오 |
| `eni_interfaces` | `security_group_names`·`security_group_ids`를 모두 비우면 전면 차단인 VPC 기본 SG가 붙는다 | RSC-ENI-05, RSC-DEF-01 | 아니오 |
| `eni_interfaces` | ENI가 인스턴스에 연결되기 전에는 그 ENI를 가리키는 경로로 트래픽이 흐르지 않는다. 연결은 호출자 몫이다 | RSC-ENI-08, RSC-ENI-09 | 아니오 |
| `eni_interfaces` | `private_ips`가 서브넷 대역 밖이거나 이미 쓰는 주소면 AWS가 apply에서 거부한다. 모듈은 검사하지 않는다 | RSC-ENI-03 | 아니오 |
| `security_groups` | `ingress`·`egress`가 비어 있는 방향은 전부 차단이다. AWS가 새 SG에 두는 아웃바운드 전체 허용 룰은 provider가 생성 시점에 회수한다 | RSC-SG-05 | 아니오 |
| `nat_gateways` | 서브넷 AZ와 NAT의 `public_subnet` AZ가 다르면 Cross-AZ 경로가 되어 데이터 전송 비용과 AZ 장애 영향이 따른다 | RSC-NAT-06 | 부분(구성은 보이나 비용은 아님) |
| `shared_public`, `stack_subnets` | `enable_ipv6 = true`에서 IPv4 룰에 대응하는 `ipv6_cidr_block` 룰이 없으면 그 서브넷의 IPv6 트래픽이 모두 차단된다 | RSC-NACL-05 | 아니오 |
| `flow_logs` | S3 대상의 버킷 정책에 `delivery.logs.amazonaws.com` 허용이 필요하고, 교차 계정 버킷은 고객 관리형 KMS 키와 그 키 정책이 전제다. 둘 다 모듈 범위 밖이다 | RSC-FLOW-06 | 아니오 |
| `flow_logs` | `kinesis-data-firehose`의 `iam_role_arn`만 검사 대상이 아니다. 같은 계정 전송에는 필요하고 교차 계정 전송에는 넣지 않으며, 둘을 구분할 정보가 입력에 없어 AWS가 apply에서 거부한다 | RSC-FLOW-03 | 아니오 |
| `flow_logs` | `destination_options`를 생략하면 블록이 렌더링되지 않아 AWS 기본값(`plain-text`, 파티션 없음)이 된다. Parquet·파티션이 필요하면 `destination_options = {}`만 적어도 세 기본값이 채워진다 | RSC-FLOW-05 | 아니오 |
| `flow_logs` | `log_format` 기본값은 AWS v2~v5 29개 필드이며 중앙 Athena 테이블 컬럼 순서와 1:1이다. 재정의는 그 테이블을 함께 바꿀 때만 한다 | RSC-FLOW-07 | 아니오 |
| `context` | `name_prefix` 길이에 따라 리소스 `name` 인자의 AWS 제약(가장 짧은 것은 IAM 롤 64자)을 넘을 수 있다. 모듈은 길이를 검사하지 않는다 | 7절 | 아니오 |
| `vpc_cidr` | 값을 바꾸면 VPC가 재생성된다 | [REQUIREMENTS 7.5절](REQUIREMENTS.md#75-수명주기-정책) | 예(`-/+`) |
| `shared_public`, `vpc_endpoint_subnets`, `stack_subnets` | 서브넷 이름·`cidr`·`az`와 스택 키를 바꾸면 서브넷이 재생성된다. `route_table`은 Association만 교체된다 | [REQUIREMENTS 7.5절](REQUIREMENTS.md#75-수명주기-정책), RSC-RT-09 | 예(`-/+`) |
| `route_tables`, `nat_gateways` | Route Table 키, NAT 키, NAT의 `public_subnet`을 바꾸면 재생성된다 | [REQUIREMENTS 7.5절](REQUIREMENTS.md#75-수명주기-정책) | 예(`-/+`) |
| `eni_interfaces` | ENI 키, `subnet`, `private_ips`를 바꾸면 재생성된다 | [REQUIREMENTS 7.5절](REQUIREMENTS.md#75-수명주기-정책) | 예(`-/+`) |
| `security_groups` | SG 키와 `description`을 바꾸면 SG가 재생성되고, 룰 키를 바꾸면 그 룰이 교체된다. 룰의 프로토콜·포트·소스는 갱신된다 | [REQUIREMENTS 7.5절](REQUIREMENTS.md#75-수명주기-정책) | 예(`-/+`) |

---

## 10. 출력 계약

| ID | 요구사항 |
| --- | --- |
| RSC-OUT-01 | 복수 리소스 출력은 리소스 키(6절)를 그대로 키로 갖는 Map으로 낸다. 예: `subnet_ids = { "web/app-a1" = "subnet-...", "shared-network/public/pub-a1" = "subnet-..." }`. 특정 범위만 모은 편의 출력(`shared_network`, `stacks.<stack>`)은 예외로 그 범위 안에서 유일한 이름을 키로 쓴다(DEC-053). |
| RSC-OUT-04 | 단일 리소스 출력은 리소스가 없으면 `null`을 낸다. 빈 문자열을 쓰지 않는다. |
| RSC-OUT-06 | 모듈은 아래 출력 표의 항목을 모두 제공한다. 항목을 추가할 수 있으나 삭제·개명은 MAJOR 변경으로 취급한다. |

| 출력 | 형식 | 내용 |
| --- | --- | --- |
| `vpc_id`, `vpc_arn`, `vpc_cidr_block`, `vpc_ipv6_cidr_block`, `vpc_owner_id` | 단일 | VPC 속성 |
| `vpc_secondary_cidr_association_ids` | CIDR → ID | 보조 CIDR 연관 |
| `igw_id`, `igw_arn`, `eigw_id` | 단일 | 게이트웨이 |
| `default_security_group_id`, `default_network_acl_id`, `default_route_table_id`, `dhcp_options_id` | 단일 | 기본 리소스 |
| `subnet_ids`, `subnet_arns`, `subnet_cidr_blocks`, `subnet_ipv6_cidr_blocks` | 서브넷 키 → 값 | Shared Public·VPC Endpoint·모든 스택 서브넷. 키 접두어(`shared-network/…`, `<stack>/…`)로 구분한다 |
| `shared_network.public_subnet_ids`, `.public_subnet_arns`, `.public_subnet_cidr_blocks` | 서브넷 이름 → 값 | Shared Public Subnet 편의 출력 |
| `shared_network.vpce_subnet_ids`, `.vpce_subnet_arns`, `.vpce_subnet_cidr_blocks` | 서브넷 이름 → 값 | VPC Endpoint Subnet 편의 출력(정의 시) |
| `nat_gateway_ids`, `nat_eip_allocation_ids`, `nat_public_ips` | NAT 키 → 값 | 모든 NAT와 EIP. `nat_public_ips`는 EIP 재사용 여부와 무관하게 NAT의 퍼블릭 IP(RSC-NAT-03) |
| `eni_ids`, `eni_arns`, `eni_private_ips` | ENI 키 → 값 | 모듈이 만든 ENI([REQUIREMENTS 6.6절](REQUIREMENTS.md#66-network-interface-eni와-security-group)). `eni_private_ips`는 기본 사설 IP(`private_ip`)이며 호출자가 인스턴스 연결에 쓴다 |
| `security_group_ids`, `security_group_arns` | SG 키 → 값 | 모듈이 만든 Security Group([REQUIREMENTS 6.6절](REQUIREMENTS.md#66-network-interface-eni와-security-group)). 호출자가 룰 리소스를 붙일 때 쓴다(RSC-SG-03). 입력 `eni_interfaces.<key>.security_group_ids`는 호출자가 만든 SG의 ID 집합이라 이름은 같고 뜻이 다르다. Endpoint 전용 SG는 `vpc_endpoint_security_group_id`로 따로 낸다 |
| `route_table_ids` | RT 키 → ID | 모든 RT. Peering 모듈에 경로 추가 대상으로 전달하는 값(5.2절) |
| `route_table_association_ids` | 서브넷 키 → ID | 모든 서브넷의 RT 연결 |
| `network_acl_ids`, `network_acl_arns` | NACL 키 → 값 | 전용 NACL |
| `stacks.<stack>.subnet_ids`와 네 유형의 `.<type>_subnet_group_names`·`.<type>_subnet_group_arns`(`db`, `elasticache`, `redshift`, `memorydb`) | 서브넷 이름 또는 그룹 키 → 값 | 스택 단위 조회 편의 출력. `subnet_ids`는 그 스택 서브넷의 이름 → ID 이며 Role별 분류를 두지 않는다(2.2절). 워크로드 모듈에 넘길 서브넷은 호출자가 이름으로 고른다. Shared Network 리소스는 넣지 않는다 |
| `vpc_endpoint_ids`, `vpc_endpoint_dns_entries`, `vpc_endpoint_security_group_id` | 서비스 → 값, 단일 | Endpoint |
| `vgw_id`, `vgw_arn`, `vgw_attachment_id` | 단일 | VGW. `vgw_attachment_id`는 `vpn_gateway.existing_id`로 기존 VGW를 연결할 때만 값이 있고 그 외에는 `null`이다(RSC-VPN-02) |
| `cgw_ids`, `cgw_arns` | CGW 키 → 값 | CGW |
| `flow_log_ids`, `flow_log_arns`, `flow_log_destination_arns` | 목적지 키 → 값 | Flow Log. 키는 `flow_logs`의 키다(RSC-FLOW-01). 목적지 리소스는 모듈이 만들지 않으므로 로그 그룹·IAM 롤 출력은 두지 않는다(RSC-FLOW-08) |
| `private_zone_id`, `private_zone_name`, `private_zone_arn` | 단일 | Private Hosted Zone |

룰 리소스(NACL 룰, Security Group 룰)는 출력하지 않는다. 룰은 상위 리소스의 키로 추적하며, 호출자가 룰을 더할 때 필요한 것은 SG ID(`security_group_ids`)뿐이다.

---

## 11. `context` 계약

모듈은 [tfmodule-context](https://github.com/oniops/tfmodule-context) 모듈의 출력 객체 `context`를 필수 입력으로 받는다. 참조 버전은 **`v1.3.5` 이상**이며 이 절이 참조 버전의 유일한 정의다. 테라폼 모듈 전체의 일관성을 위해 `v1.3.5` 미만 버전의 출력은 허용하지 않는다. 이 모듈이 쓰는 `name_prefix`·`tags`·`region`·`pri_domain` 등 출력 필드의 스키마는 `v1.3.5`에서 확정되었고, 여러 모듈이 같은 `context` 계약을 공유해야 리소스 이름과 태그가 조직 전체에서 일관되기 때문이다. `module "ctx"`와 `module "vpc"`를 함께 호출하는 예시는 README Usage 절에 둔다.

`context`가 제공하는 값과 모듈에서의 용도는 다음과 같다.

| 필드 | 용도 |
| --- | --- |
| `name_prefix` | 모든 리소스 이름의 접두어. 별도 `vpc_name` 입력을 두지 않는다 |
| `tags` | 모든 리소스 태그 병합의 1단계([REQUIREMENTS 7.3절](REQUIREMENTS.md#73-태그-정책)) |
| `region` | Interface VPC Endpoint 서비스 이름(`com.amazonaws.<region>.<service>`) 구성. 리소스 배치 리전은 호출자의 `provider` 가 정하며 별도 `region` 입력을 두지 않는다 |
| `pri_domain` | Private DNS 도메인과 DHCP 도메인 기본값 |
| `region_alias`, `project`, `environment`, `env_alias`, `owner`, `team`, `cost_center` | 모듈이 직접 쓰지 않는다. tfmodule-context가 `name_prefix`와 `tags`를 만들 때 이미 반영한 값이며 `optional()`로 받는다 |

- 모듈의 `variable "context"`는 참조 버전 출력 `context`의 **부분집합**이다. 모듈이 쓰는 `name_prefix`, `tags`, `region`, `pri_domain`만 필수 필드로 두고 위 표의 나머지 필드는 `optional()`로 받는다. 표에 없는 출력 필드는 타입에 두지 않으며 Terraform이 변환 시 버린다. 타입 골격은 8.1절이 정의한다.
- 필수 필드라도 값이 `null`일 수 있다. Terraform은 필수 속성에 `null`을 허용하므로 `pri_domain`과 `region`은 그 값을 쓰는 시점에 `null`이면 plan 단계에서 실패시킨다. `pri_domain`은 `domain_name`을 생략한 DHCP Options·Private Hosted Zone에서(RSC-DEF-04, RSC-DNS-01), `region`은 Interface VPC Endpoint를 만들 때(RSC-VPCE-02) 그 대상이다. `name_prefix`와 `tags`는 모든 리소스가 쓰므로 `null`이면 어느 리소스에서든 실패한다.
- 이름 접두어를 `context` 외의 입력으로 덮어쓰는 기능은 제공하지 않는다. 태그는 [REQUIREMENTS 7.3절](REQUIREMENTS.md#73-태그-정책) 병합 순서에 따라 덮어쓸 수 있으나 보호 키는 예외다.
- 리소스 이름(`Name` 태그) 규칙은 7절을 따른다.
- 호출자는 `module "ctx"`의 `source`에 `?ref=`로 `v1.3.5` 이상의 태그를 고정한다. 더 낮은 태그를 참조하면 출력 스키마 불일치로 `terraform validate`·`plan`이 실패하거나, 이 모듈이 쓰는 필드가 비어 태그가 조용히 누락될 수 있다. 검증 방법은 [REQUIREMENTS 8.3절](REQUIREMENTS.md#83-terraform-버전)을 따른다.

입력 변수 전체 목록과 타입은 8.1절이 유일한 정의다.

---

## 12. 코드 컨벤션

REQUIREMENTS 7절이 정한 강제 규칙을 코드로 어떻게 구성하는지 정의한다. 2~5절(모델)과 6~11절(계약)을 만족하는 리소스 코드는 이 절의 형식을 따른다.

- 모든 리소스는 `for_each`와 Map 키로 작성한다. 키는 호출자가 입력에서 정한 이름으로만 구성하고 목록 순서나 인덱스에서 파생하지 않는다. 배열 인덱스(`count` + `element()`)는 쓰지 않는다.
- 복수 리소스 출력과 단일 리소스가 없을 때의 처리는 10절(출력 계약)의 RSC-OUT-01·04가 정의한다. 편의 출력은 그 범위 안에서 유일한 이름을 키로 쓸 수 있다.
- 리소스 이름은 `context.name_prefix` 를 접두어로 하고 역할을 나타내는 접미어를 붙인다. 리소스별 이름 규칙은 7절 표를 따르고 표에 없는 예외를 만들지 않는다.
- 태그는 `merge(<조직 공통 태그>, <사용자 커스텀 tags>, { Name })` 순서로 병합하고, 뒤 단계가 앞 단계의 같은 키를 덮어쓴다. 커스텀 `tags` 는 모듈 공통 하나와 리소스 인스턴스별 하나를 두며 리소스 유형별 태그 입력은 두지 않는다. 모듈이 만드는 태그는 `Name` 하나이며 보호 키도 `Name` 하나다. 이 모듈의 병합 대상과 각 단계에 들어가는 입력은 [REQUIREMENTS 7.3절](REQUIREMENTS.md#73-태그-정책)이 정의한다.
- 모듈 안에 `provider` 블록, `backend` 블록, 하드코딩된 리전이나 계정 ID 를 두지 않는다. 리소스 배치 리전은 호출자의 `provider` 가 정하고, 리전 값이 필요하면 `context.region` 을 쓴다.
- 입력·출력을 추가하거나 바꾸면 README 의 Input Variables 표와 Outputs 표를 같은 커밋에서 갱신한다. 설명은 한글로 쓴다.
- 리소스 키 산식이나 이름 규칙을 바꾸면 이미 배포된 리소스에서 재생성이 일어난다. 이런 변경은 사용자에게 먼저 알리고 MAJOR 를 올린다. 릴리스 절차는 `CLAUDE.md` Git 작업 규칙을 따른다.
- `terraform fmt` 는 자신이 수정한 파일에만 적용한다. 기존 정렬 차이를 정리할 때는 기능 변경과 섞지 않고 포맷 전용 커밋으로 분리한다.

리소스 하나를 만드는 모듈의 태그 병합은 다음과 같다. 여러 리소스를 만드는 모듈은 인스턴스별 `tags` 를 `var.tags` 뒤에 더한다.

```hcl
resource "aws_instance" "this" {
  tags = merge(context.tags, var.tags, { Name = "${context.name_prefix}-ec2" })
}
```

### 12.1 입력 변수 정의 규칙

- 입력 변수는 리소스 인자에 그대로 대응되는 구조로 정의한다. 리소스에 연결되지 않는 입력 변수를 두지 않는다.
- 입력 변수는 영문 `description` 을 가지며 선택 입력만 `default` 를 가진다.
- 여러 개를 받는 입력은 `list` 대신 이름을 키로 하는 `map(object({...}))` 로 정의한다. 선택 필드는 `optional()` 로 기본값을 타입 정의에 둔다.
- 정적 기본값은 타입 정의에 두고, 다른 입력이나 AWS 에서 파생되는 기본값은 `null` 로 받아 `description` 에 파생 규칙을 명시한다. 파생 원본이 `null` 이면 plan 단계에서 실패시킨다.
- 참조는 하위 항목이 상위 키 하나를 적는 방향으로 둔다. 상위가 하위를 나열하는 입력을 두지 않으며, 예외는 AWS 리소스 인자 자체가 목록인 경우뿐이다.

### 12.2 히어독 설명

구조가 복잡한 변수(`map(object({...}))`, 중첩 `object` 등)는 `description = <<-EOF ... EOF` 히어독 형식으로 작성한다. 첫 문단에 변수의 의미와 키·필드 역할을 설명하고, 이어서 호출 시 그대로 복사해 쓸 수 있는 사용 예시(HCL)를 반드시 함께 기술한다. 예시 값은 샘플 CIDR·이름만 쓴다.

아래는 히어독 작성 형식을 보이는 예시이며 타입의 정본이 아니다. 이 모듈이 실제로 쓰는 변수 타입은 [8.1·8.2절](#8-입력-계약)이 정의한다.

```hcl
variable "stack_subnets" {
  type = map(object({
    tags = optional(map(string), {})
    subnets = map(object({
      az          = string
      cidr        = string
      route_table = string
      ipv6_index  = optional(number)
      tags        = optional(map(string), {})
    }))
    db_subnet_group          = optional(map(set(string)), {})
    elasticache_subnet_group = optional(map(set(string)), {})
  }))
  default     = {}
  description = <<-EOF
Map of workload stacks keyed by stack name. Each stack owns a flat map of subnets keyed by subnet name; there is no role layer. A subnet entry carries its Availability Zone ID, CIDR, and the route table key it is associated with, so one line fully describes where the subnet sits and how it egresses. Stack tags apply to every subnet in the stack; subnet tags apply to that subnet only.

  stack_subnets = {
    web = {
      tags = { Stack = "web" }
      subnets = {
        app-a1  = { az = "apne2-az1", cidr = "10.100.10.0/24", route_table = "pri-a1" }
        app-c1  = { az = "apne2-az3", cidr = "10.100.11.0/24", route_table = "pri-c1" }
        data-a1 = { az = "apne2-az1", cidr = "10.100.20.0/24", route_table = "iso" }
        data-c1 = { az = "apne2-az3", cidr = "10.100.21.0/24", route_table = "iso" }
      }
      db_subnet_group = {
        data = ["data-a1", "data-c1"]
      }
    }
  }
EOF
}
```

### 12.3 Terraform 설계 원칙

- 멱등성을 최우선한다. 리소스를 동적으로 추가하거나 제거해도 이미 구성된 다른 리소스에 변경(`~`)이나 재생성(`-/+`)이 생기지 않아야 한다.
- 리소스 키는 12절의 `for_each`·Map 키 규칙을 따른다.
- 코드는 일관된 템플릿으로 작성해 같은 종류의 리소스 그룹을 같은 형태로 추가하고 제거할 수 있어야 한다. 한 그룹에만 예외 구조를 두지 않는다.
- 복잡한 구조 변환을 `locals` 에서 수행하지 않는다. 핵심 로직이라도 입력이 리소스 인자에 그대로 대응되도록 체계적인 구조의 `variables`(object, map 타입)를 먼저 정의한다.
- 가독성을 우선한다. 사용자가 `variables.tf` 와 README 만 읽고 모듈을 직관적으로 이해하고 바로 호출할 수 있어야 한다. 삼항 연산자나 조건식을 한 줄에 겹쳐 쓰지 않는다.
- 외부 모듈이 이 모듈의 리소스에 항목을 추가할 수 있어야 하는 경우(예: 다른 모듈이 Route Table 에 경로를 넣는 경우) 인라인 블록 대신 독립 리소스로 만들어 이 모듈의 plan 에 변경이 생기지 않게 한다.

---

## 13. EKS 스택

EKS 클러스터를 이 VPC 위에 올릴 때 서브넷에 필요한 태그를 안내한다. EKS 스택은 다른 스택과 같은 `stack_subnets` 항목이며 새 라우팅·NAT·NACL 규칙을 도입하지 않는다. 모듈은 이 태그를 만들지 않고 호출자가 서브넷 `tags`, `shared_public.tags`, 스택 `tags` 중 아래 표가 정한 위치에 직접 적는다.

### 13.1 기본 원칙

- EKS 스택은 다른 스택과 같은 `stack_subnets` 항목이며 새 라우팅, NAT, NACL 규칙을 도입하지 않는다(2.2절). 어느 서브넷이 어디로 나가는지는 그 서브넷의 `route_table`이 정한다(2.2절 권장 용도 표).
- EKS 스택의 Private 통신 정책과 모듈 구현 범위는 5.1절을 따른다. Pod-to-Pod, Namespace 접근 통제는 Kubernetes 계층의 책임이다.

### 13.2 Role별 권장 태그

| 대상 | 태그 | 값 | 필요 조건 |
| --- | --- | --- | --- |
| 노드 서브넷 줄 `tags` | `kubernetes.io/role/internal-elb` | `1` | AWS Load Balancer Controller가 Internal LB 서브넷을 자동 탐색할 때 |
| 노드 서브넷 줄 `tags` | `karpenter.sh/discovery` | `<cluster_name>` | Karpenter 사용 시. Node가 생성될 서브넷에만 |
| `shared_public.tags` 또는 Public 서브넷 줄 `tags` | `kubernetes.io/role/elb` | `1` | Internet-facing LB 서브넷 자동 탐색 |
| 노드 서브넷과 Public 서브넷 줄 `tags` | `kubernetes.io/cluster/<cluster_name>` | `shared` | 구버전 AWS Load Balancer Controller, 기존 조직 표준 등 호환성이 필요할 때만. 최신 EKS 구성에서는 불필요 |
| 스택 `tags` | `ClusterName` | `<cluster_name>` | 조직 식별용(선택). 스택 `tags`이므로 서브넷뿐 아니라 그 스택의 NACL 과 네 종류의 Subnet Group 에도 적용된다([REQUIREMENTS 7.3.1절](REQUIREMENTS.md#731-각-태그-입력이-적용되는-리소스)) |

- 데이터 계층·캐시 서브넷 줄에는 `kubernetes.io/*`, `karpenter.sh/*` 태그를 두지 않는다. 특히 `karpenter.sh/discovery`가 붙으면 Karpenter가 그 서브넷에 노드를 띄울 수 있다. 같은 이유로 컨트롤러 태그를 스택 `tags`로 올리지 않는다.
- 한 VPC에 EKS 스택이 여러 개면 `karpenter.sh/discovery`와 `kubernetes.io/cluster/*`는 스택마다 자기 `cluster_name`으로 정의한다. 값이 클러스터와 무관한 `kubernetes.io/role/elb`·`internal-elb`는 여러 클러스터가 공유할 수 있고, Shared Public Subnet을 여러 클러스터가 쓰면 각 클러스터의 `kubernetes.io/cluster/<cluster_name>` 태그를 함께 둔다.
- Karpenter가 탐색하는 Security Group 태그는 EKS 노드 SG의 몫이며 워크로드 모듈이 만든다. 이 모듈이 만드는 SG는 자기가 만든 ENI에 붙이는 것뿐이고([REQUIREMENTS 6.6절](REQUIREMENTS.md#66-network-interface-eni와-security-group)), EKS 스택에는 서브넷 태그만 관여한다.

### 13.3 예시

전체 예시는 [REQUIREMENTS 8.4절](REQUIREMENTS.md#84-기준-입력)의 `eks` 기준 입력이다(저장소에 두지 않는 로컬 검증 자산이다). 3 AZ에 EKS 스택 5개(`svc`, `auction`, `cms`, `toolchain`, `obsv`)를 두고 VPC Endpoint Subnet, Interface Endpoint, 스택 NACL, Flow Log를 함께 선언한다. 아래는 그 파일에서 Shared Public 과 `svc` 스택을 2개 AZ 로 줄여 발췌한 것이다. `context`, `vpc_cidr`, `nat_gateways`, `route_tables`(`pub`, `pri-a1`, `pri-c1`, `isolated`) 선언을 생략했으므로 이 블록만으로는 plan 할 수 없다. 단독 plan 은 `eks` 기준 입력 전체로 한다. 발췌 자체는 AZ 2개 이상(RSC-AZ-02)과 DB Subnet Group 멤버 2 AZ 이상(RSC-SUB-05) 제약을 지킨다.

```hcl
# Shared Public. 공통 tags 가 그 아래 모든 서브넷에 적용된다.
shared_public = {
  tags = { "kubernetes.io/role/elb" = "1" }
  subnets = {
    pub-a1 = { az = "apne2-az1", cidr = "10.100.0.0/24", route_table = "pub" }
    pub-c1 = { az = "apne2-az3", cidr = "10.100.1.0/24", route_table = "pub" }
  }
}

stack_subnets = {
  svc = {
    # 스택 tags: 이 스택의 모든 서브넷, NACL, DB Subnet Group 에 적용된다.
    tags = {
      ClusterName = "dxplat-an2p-svc-eks"
      ServiceRole = "workload"
      Stack       = "svc"
    }

    # 서브넷 평면 Map. 계층은 이름으로, 성격은 route_table 로 나타낸다. Role 계층은 없다.
    # 컨트롤러 태그는 노드 서브넷 줄에만 적어 데이터 계층 서브넷에 붙지 않게 한다(13.2절).
    subnets = {
      svc-node-a1 = { az = "apne2-az1", cidr = "10.100.32.0/21", route_table = "pri-a1", tags = { "kubernetes.io/role/internal-elb" = "1", "karpenter.sh/discovery" = "dxplat-an2p-svc-eks" } }
      svc-node-c1 = { az = "apne2-az3", cidr = "10.100.40.0/21", route_table = "pri-c1", tags = { "kubernetes.io/role/internal-elb" = "1", "karpenter.sh/discovery" = "dxplat-an2p-svc-eks" } }
      svc-data-a1 = { az = "apne2-az1", cidr = "10.100.56.0/24", route_table = "isolated" }
      svc-data-c1 = { az = "apne2-az3", cidr = "10.100.57.0/24", route_table = "isolated" }
    }

    db_subnet_group = {
      svc-data = ["svc-data-a1", "svc-data-c1"]
    }
  }
}
```
