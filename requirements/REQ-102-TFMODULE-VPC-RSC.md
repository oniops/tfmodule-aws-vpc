# AWS VPC Terraform 모듈 - 리소스별 요구사항 정의서

<!-- 문서 계층: REQ-101(BASE, 공통 전제) → REQ-102(RSC, 이 문서: 리소스별 요구사항) → REQ-103(EKS, 스택 태그 안내). 모듈은 이 세 문서를 기준으로 새로 구현한다. 현재 저장소의 코드와 README는 참고 자료이며 요구사항의 근거가 아니다. 작성일 2026-09-10, 개정 2026-09-11. -->

## 1. 목적과 범위

본 문서는 `REQ-101-TFMODULE-VPC-BASE.md`가 정한 공통 전제(스택 모델, 명시적 Route Table·NAT 선언, 안정적 Resource Key, Billing Tag, 입력 모델) 위에서 VPC 모듈이 만들어 내는 **각 리소스가 충족해야 하는 요구사항**을 정의한다.

- 범위: VPC 본체, Shared Public Network, 스택 서브넷, NAT, Route Table, NACL, 기본 리소스, VPC Endpoint, VPC Peering, VGW/CGW, Flow Logs, Private DNS, 출력, 입력 변수 구조.
- 제외: EKS 스택에 필요한 서브넷 태그 안내(`REQ-103-TFMODULE-VPC-EKS.md`), 구현 방식·코드 구조.
- 공통 전제는 REQ-101을 그대로 따르며 이 문서에서 다시 정의하지 않는다. 충돌 시 REQ-101이 우선한다.
- 요구사항 ID는 `RSC-<영역>-<번호>` 형식이다.

## 2. 공통 규칙의 리소스 적용 방식

### 2.1 리소스 키 체계

REQ-101 5절의 `for_each` 기반 안정 키를 모든 리소스에 확장한다. 키는 호출자가 입력에서 정한 이름으로만 구성하며 목록 순서·인덱스·AZ에서 파생하지 않는다. 서브넷과 Route Table의 이름은 호출자가 정하고 모듈은 접두어와 유형 접미어만 붙인다(2.2절). NAT는 자신을 선언한 Route Table의 키를 쓴다.

| 리소스 | 키 형식 | 예시 |
| --- | --- | --- |
| Shared Public Subnet | `shared-network/public/<name>` | `shared-network/public/pub-a1` |
| Shared Private Subnet (선택) | `shared-network/private/<name>` | `shared-network/private/vpce-a1` |
| Stack Subnet | `<stack>/<role>/<name>` | `web/private/app-a1`, `web/database/data-a1` |
| Stack Dedicated Public Subnet | `<stack>/public/<name>` | `web/public/pub-a1` |
| Route Table | `<rt_key>` (`route_tables` 키) | `pub`, `pri-a1` |
| NAT Gateway, EIP | `<rt_key>` (`default_route = "nat"`인 Route Table의 키) | `pri-a1` |
| Route | `<rt_key>/<destination>` | `pri-a1/0.0.0.0/0` |
| Route Table Association | Subnet 키와 동일 | `web/private/app-a1` |
| Network ACL | `<stack>` 또는 `shared-network/public` | `web` |
| Network ACL Rule | `<nacl_key>/<direction>/<rule_name>` | `web/ingress/allow-app-tier` |
| VPC Endpoint | `<service>` (Gateway는 `s3`, `dynamodb`) | `ecr.api` |
| Gateway Endpoint RT 연결 | `<service>/<rt_key>` | `s3/pri-a1` |
| VPC Peering | `<peer_key>` | `observability-central` |
| Customer Gateway | `<cgw_key>` | `hq-fw-1` |
| Secondary CIDR | `<cidr>` | `100.64.0.0/16` |
| DB Subnet Group | `<db_subnet_group>` (스택 `db_subnet_groups`의 키) | `data` |

### 2.2 이름 규칙

이름 접두어 `<prefix>`는 필수 입력 `context.name_prefix`로 한다(REQ-101 9.1절). 모든 리소스의 `Name` 태그는 REQ-101 9.1절의 원칙에 따라 `<prefix>-<키>-<유형 접미어>`이며, 키가 없는 단일 리소스는 `<prefix>-<유형 접미어>`다. 모듈은 스택·Role·AZ를 조합해 이름을 만들어 내지 않는다. 예를 들어 `name_prefix = "dxplat-an2p"`, 서브넷 키 `blb-a1`이면 서브넷 이름은 `dxplat-an2p-blb-a1-sn`이고, Route Table 키 `pri-a1`이면 Route Table은 `dxplat-an2p-pri-a1-rt`, 그 NAT는 `dxplat-an2p-pri-a1-nat`이다.

| 리소스 | Name 태그 | 키 출처 |
| --- | --- | --- |
| VPC | `<prefix>-vpc` | 없음 |
| Internet Gateway | `<prefix>-igw` | 없음 |
| Egress-only IGW | `<prefix>-eigw` | 없음 |
| Subnet (Shared, Stack 모두) | `<prefix>-<name>-sn` | 서브넷 키 |
| Route Table | `<prefix>-<rt_key>-rt` | `route_tables` 키 |
| NAT Gateway | `<prefix>-<rt_key>-nat` | NAT를 선언한 Route Table 키 |
| EIP | `<prefix>-<rt_key>-eip` | NAT를 선언한 Route Table 키 |
| Network ACL | `<prefix>-<stack>-nacl`, Shared Public은 `<prefix>-public-nacl` | NACL 키 |
| 기본 SG / RT / NACL | `<prefix>-default-sg`, `<prefix>-default-rt`, `<prefix>-default-nacl` | 없음 |
| DB Subnet Group | `<prefix>-<db_subnet_group>-sng` | 스택 `db_subnet_groups`의 키 |
| VPC Endpoint / Endpoint SG | `<prefix>-<service>-vpce`, `<prefix>-vpce-sg` | 서비스 이름 |
| Peering | `<prefix>-<peer_key>-pcx` | `peer_vpcs` 키 |
| VGW / CGW | `<prefix>-vgw`, `<prefix>-<cgw_key>-cgw` | 없음 / `customer_gateways` 키 |
| Flow Log | `<prefix>-vpc-flow` | 없음 |
| Private Hosted Zone | 도메인 이름 | 없음 |
| DHCP Options | `<prefix>-dhcp` | 없음 |

- 서브넷 이름은 VPC 전체(Shared와 모든 스택)에서 유일해야 한다. 같은 이름이 두 곳에 있으면 `Name` 태그가 겹치므로 plan 실패.
- 호출자가 정하는 이름 키(스택, 서브넷, Route Table, NACL 룰, Peering, CGW, DB Subnet Group)에는 소문자, 숫자, `-`만 허용한다. 위반 시 plan 실패. AWS 서비스 이름(`ecr.api`)과 CIDR처럼 AWS 값 자체가 키인 경우는 이 규칙의 대상이 아니다.

### 2.3 태그 규칙

태그 병합 순서, 보호 키, 리소스 범위 태그 값, Billing Tag는 REQ-101 8절을 따르며 여기서 다시 정의하지 않는다. 이 모듈의 리소스가 REQ-101 8.2절의 어느 범위에 속하는지는 다음과 같다.

| 리소스 | REQ-101 8.2절 범위 |
| --- | --- |
| VPC, IGW, Egress-only IGW, Shared Public/Private Subnet, `stack`이 없는 RT와 그 NAT, Shared Public NACL(`public_subnets_nacl`), 기본 SG/RT/NACL, VPC Endpoint와 Endpoint SG, Peering, VGW, CGW, Flow Log, PHZ, DHCP | Shared Network 리소스 |
| Stack Subnet | Stack 서브넷 |
| `stack`이 지정된 RT와 그 NAT, Stack NACL, DB Subnet Group | Stack 전용 그 외 리소스 |

- 리소스 유형별 추가 태그(REQ-101 8.1절 2단계)는 단일 입력 `resource_tags` 객체로 받는다. 필드는 리소스 유형별 `map(string)`이며 모두 선택이다: `vpc`, `igw`, `eigw`, `public_subnet`, `shared_private_subnet`, `stack_subnet`, `route_table`, `nat_gateway`, `eip`, `network_acl`, `db_subnet_group`, `default_security_group`, `default_route_table`, `default_network_acl`, `dhcp_options`, `vpc_endpoint`, `vpc_endpoint_security_group`, `peering`, `vpn_gateway`, `customer_gateway`, `flow_log`, `private_zone`. `resource_tags`에도 REQ-101 8.1절 보호 키 검사를 적용한다.
- 인스턴스별 커스텀 `tags`(REQ-101 8.1절 3단계)는 스택, 서브넷 AZ 그룹, Route Table, Peering, CGW가 가진다. AZ 그룹 `tags`는 그 그룹의 모든 서브넷에 적용되고, Route Table `tags`는 그 RT와 NAT·EIP에 적용된다.

### 2.4 검증과 실패 원칙

- 입력 조합이 유효하지 않으면 `plan` 단계에서 `validation` 또는 `precondition`으로 실패해야 한다. 조건 미달을 이유로 리소스를 조용히 0개 만들지 않는다.
- AZ는 가능하면 AZ ID(`apne2-az1`)로 받아 `availability_zone_id`에 그대로 적용한다. AZ ID는 계정마다 다른 AZ 이름과 달리 물리 AZ를 가리키므로 계정 간 배치를 일관되게 한다. AWS 리소스 인자가 AZ 이름만 받는 경우(예: VGW의 `availability_zone`)에 한해 AZ 이름을 받으며, 해당 필드의 변수 설명에 AZ 이름임을 명시한다.
- 모든 서브넷의 CIDR은 VPC CIDR 또는 보조 CIDR 안에 있어야 하고 서로 겹치지 않아야 한다. 위반 시 plan 실패.
- 입력이 다른 입력의 키를 참조하는 경우(`route_table`, `nat_public_subnet`, `stack`, `route_tables`, `propagate_to`) 참조 대상 키가 존재하지 않으면 plan 실패.

### 2.5 수명주기 원칙

- 스택, 서브넷, Route Table, NACL 룰, Peering, CGW의 추가·제거는 해당 키의 리소스만 생성·삭제한다. 다른 키의 plan 결과는 변경(`~`)·재생성(`-/+`) 0건이어야 한다.
- 생성 후 변경이 곧 재생성을 뜻하는 입력(`vpc_cidr`, 서브넷 CIDR·이름·AZ 그룹, 스택 키, Route Table 키, `nat_public_subnet`)은 변수 설명에 "변경 시 재생성"을 명시한다.

## 3. 리소스별 요구사항

### 3.1 VPC 본체

| ID | 요구사항 |
| --- | --- |
| RSC-VPC-01 | `vpc_cidr` 1개를 필수 입력으로 받는다. 기본값을 두지 않는다. |
| RSC-VPC-02 | `secondary_cidrs`는 CIDR 문자열을 키로 하는 집합으로 받아 항목별 `aws_vpc_ipv4_cidr_block_association`을 만든다. 항목 추가·삭제가 다른 항목에 영향을 주지 않는다. |
| RSC-VPC-03 | 보조 CIDR을 쓰는 서브넷은 보조 CIDR 연관 리소스가 삭제되기 전에 먼저 삭제되도록 의존성을 보장한다. |
| RSC-VPC-04 | DNS 지원과 DNS 호스트 이름은 항상 활성이다. 끄는 입력을 두지 않는다. 인스턴스 테넌시는 `default`로 고정한다. |
| RSC-VPC-05 | IPv6는 `enable_ipv6`(기본 `false`)로 **선택적으로 지원**한다. 켜면 Amazon 제공 /56을 할당하고, 서브넷별 IPv6 /64 인덱스는 AZ 그룹의 `ipv6_indexes`(서브넷 이름 → 인덱스 Map)로 받는다. IPv6가 꺼져 있으면 IPv6 관련 리소스·경로가 0개다. |

### 3.2 가용 영역

| ID | 요구사항 |
| --- | --- |
| RSC-AZ-01 | `azs`는 AZ ID 목록이며 최소 2개를 요구한다. 1개면 plan 실패. |
| RSC-AZ-02 | 모든 서브넷 AZ 그룹의 키는 `azs`에 포함된 AZ ID여야 한다. 포함되지 않으면 plan 실패. |
| RSC-AZ-03 | `azs`에 AZ를 추가하면 기존 AZ의 리소스는 변경되지 않는다. AZ 제거 시 판정은 RSC-AZ-02를 따른다. |

### 3.3 Shared Public Network (Public Subnet, IGW, Egress-only IGW)

서브넷 AZ 그룹 객체의 공통 구조는 다음과 같다. `public_subnets`, `shared_private_subnets`, 스택 `subnets.<role>`이 모두 같은 구조를 쓴다.

| 필드 | 타입 | 내용 |
| --- | --- | --- |
| (키) | AZ ID | 그룹의 배치 AZ |
| `route_table` | `string`, 필수 | 그룹의 모든 서브넷이 연결되는 `route_tables` 키 |
| `subnets` | `map(string)`, 필수 | 서브넷 이름 → CIDR. 1개 이상 |
| `tags` | `map(string)`, 선택 | 그룹의 모든 서브넷에 적용하는 커스텀 태그 |
| `ipv6_indexes` | `map(number)`, 선택 | 서브넷 이름 → IPv6 /64 인덱스. `enable_ipv6`일 때만 |

| ID | 요구사항 |
| --- | --- |
| RSC-PUB-01 | `public_subnets`는 AZ ID를 키로 하는 AZ 그룹 Map이다. 각 그룹의 `subnets`가 Shared Public Subnet이 된다. |
| RSC-PUB-02 | Shared Public Subnet은 `Stack = shared-network`로 태깅되며 모든 스택이 NAT·Public LB 배치에 공용으로 쓴다. |
| RSC-PUB-03 | 스택 입력에 `subnets.public`이 있으면 해당 스택 전용 Public Subnet을 만들고 스택 태그를 붙인다(REQ-101 3절 Dedicated Public). |
| RSC-PUB-04 | Shared Public Subnet과 스택 전용 Public Subnet의 AZ 그룹은 `default_route = "igw"`인 Route Table을 참조해야 한다. 다른 값이면 plan 실패. IGW Route Table은 호출자가 `route_tables`에 선언하며 모듈이 자동으로 만들지 않는다. |
| RSC-PUB-05 | IGW는 Public Subnet(공용 또는 전용)이 1개 이상일 때 1개 생성하고, 없으면 만들지 않는다. 별도 입력을 두지 않는다. |
| RSC-PUB-06 | Egress-only IGW는 IPv6가 켜져 있고 `default_route = "nat"` Route Table이 1개 이상일 때 1개 생성한다. |
| RSC-PUB-07 | `shared_private_subnets`(AZ 그룹 Map, 선택, 기본 `{}`)는 Interface VPC Endpoint ENI 배치 전용이다. 그룹은 `default_route = "none"` Route Table을 참조해야 하고 `subnets`는 AZ마다 1개여야 한다. 이 두 제약은 Interface Endpoint가 AZ당 서브넷 1개만 받고 인터넷 경로가 필요 없다는 데서 오며, REQ-101 3.1절 스택 Role 표는 여기에 적용하지 않는다. 정의하지 않으면 관련 리소스가 0개이며, 정의하면 `Stack = shared-network`로 태깅한다. |

### 3.4 Workload Stack Subnet Set

스택 서브넷은 `stack_subnets.<stack>.subnets.<role>.<az>.subnets.<name>`으로 정의한다. Role 정의, 허용되는 기본 경로, 격리 원칙은 REQ-101 3.1절을 따르며 여기서 다시 정의하지 않는다. 아래는 Role별로 이 모듈이 만드는 리소스 차이만 적는다.

| Role | 이 모듈에서의 리소스 차이 |
| --- | --- |
| `public` | RSC-PUB-03 참조 |
| `private` | 없음 |
| `database` | RSC-SUB-05의 DB Subnet Group |
| `intra` | 없음 |

| ID | 요구사항 |
| --- | --- |
| RSC-SUB-01 | 스택 `subnets`의 1단계 키는 Role, 2단계는 3.3절의 AZ 그룹 객체다. 서브넷 이름은 AZ 그룹 `subnets`의 키이고 값은 CIDR이다. |
| RSC-SUB-02 | 각 스택은 `private` Role 서브넷을 1개 이상 가져야 한다. 없으면 plan 실패. `database`, `intra`, `public`은 선택이다. |
| RSC-SUB-03 | Role별로 `azs`의 모든 AZ를 채우도록 강제하지 않으며, 한 AZ 그룹 안에 서브넷을 여러 개 둘 수 있다. |
| RSC-SUB-04 | AZ 그룹이 참조하는 Route Table의 `default_route`가 REQ-101 3.1절 표에서 그 Role에 허용된 값이 아니면 plan 실패. `stack`이 지정된 Route Table을 다른 스택의 AZ 그룹이 참조하면 plan 실패. |
| RSC-SUB-05 | 스택의 `db_subnet_groups`는 그룹 이름을 키로 하고 서브넷 이름 집합을 값으로 하는 Map(선택, 기본 `{}`)이다. 항목마다 `aws_db_subnet_group` 1개를 만들고 나열한 서브넷만 넣는다. 이름은 `<prefix>-<db_subnet_group>-sng`. 나열하지 않은 `database` 서브넷은 어느 그룹에도 속하지 않는다. 다음이면 plan 실패: 멤버가 같은 스택의 `database` Role 서브넷이 아닐 때, 멤버가 2개 AZ 미만일 때(AWS 제약), 그룹 이름이 다른 스택의 그룹 이름과 겹칠 때. |
| RSC-SUB-06 | 서브넷 태그는 REQ-101 8.1절 병합 순서와 보호 키 규칙을 따른다. AZ 그룹 `tags`는 3단계 커스텀 태그다. |
| RSC-SUB-07 | 스택 제거 시 그 스택의 서브넷, NACL, DB Subnet Group, `stack`이 그 스택인 RT와 NAT만 삭제되고 다른 스택과 Shared 리소스는 변경되지 않는다. |
| RSC-SUB-08 | 스택 키와 서브넷 이름 변경은 재생성으로 간주한다. 변수 설명에 명시하고, 필요하면 호출자가 `moved` 블록을 쓰도록 안내한다. |

### 3.5 NAT Gateway와 EIP

REQ-101 4절에 따라 NAT는 `default_route = "nat"`인 Route Table마다 1개 만들며 별도 입력을 두지 않는다.

| ID | 요구사항 |
| --- | --- |
| RSC-NAT-01 | `default_route = "nat"`인 Route Table은 `nat_public_subnet`(Shared Public Subnet 이름)을 필수로 가진다. 모듈은 그 Route Table 키로 NAT 1개와 EIP 1개를 만들어 지정한 Public Subnet에 배치한다. |
| RSC-NAT-02 | `nat_public_subnet`은 `public_subnets`의 어느 AZ 그룹에든 있는 서브넷 이름이어야 한다. 스택 전용 Public Subnet은 지정할 수 없다. 없으면 plan 실패. |
| RSC-NAT-03 | Route Table의 선택 필드 `eip_allocation_id`가 있으면 EIP를 만들지 않고 그 allocation을 연결하며, 퍼블릭 IP는 allocation ID로 조회해 `nat_public_ips` 출력에 같은 키로 싣는다(RSC-OUT-03). |
| RSC-NAT-04 | NAT와 EIP의 태그 범위는 자신을 선언한 Route Table을 따른다(2.3절). |
| RSC-NAT-05 | 한 NAT를 여러 Route Table이 공유하는 구성은 지원하지 않는다. 여러 AZ의 서브넷이 NAT 1개를 쓰려면 그 서브넷들이 같은 `nat` Route Table을 참조한다. |
| RSC-NAT-06 | `nat` Route Table을 참조하는 AZ 그룹의 AZ가 `nat_public_subnet`의 AZ와 다르면 Cross-AZ 경로가 된다. 모듈은 이를 허용하되 변수 설명에 비용·장애 영향을 명시한다. |

### 3.6 Route Table, Route, Association

REQ-101 5절에 따라 Route Table은 `route_tables` 입력에 선언된 항목만 만든다. 모듈이 스스로 만드는 Route Table은 없다.

| ID | 요구사항 |
| --- | --- |
| RSC-RT-01 | `route_tables`는 호출자가 정한 키의 Map이다. 값은 `default_route`(필수, `igw`·`nat`·`none`), `nat_public_subnet`(`nat`일 때 필수, `public_subnets`의 서브넷 이름), 선택 `eip_allocation_id`(`nat`일 때만), 선택 `stack`, 선택 `tags`를 가진다. `nat` 이외에서 `nat_public_subnet`이나 `eip_allocation_id`를 주면 plan 실패. 예약 키는 없다. |
| RSC-RT-02 | `default_route`에 따라 기본 경로를 만든다. `igw`는 `0.0.0.0/0 → IGW`, `nat`는 `0.0.0.0/0 → 그 RT의 NAT`, `none`은 기본 경로 없음. 그 외 경로는 만들지 않는다. |
| RSC-RT-03 | 어떤 AZ 그룹도 참조하지 않는 Route Table은 plan 실패로 알린다. |
| RSC-RT-04 | 경로 리소스 키는 `<rt_key>/<destination>`이며 같은 RT에 같은 목적지가 두 번 정의되면 plan 실패. |
| RSC-RT-05 | IPv6가 켜져 있으면 `nat` RT에 `::/0 → Egress-only IGW`, `igw` RT에 `::/0 → IGW` 경로를 추가한다. |
| RSC-RT-06 | Gateway Endpoint(S3, DynamoDB)는 `vpc_endpoints.gateway`가 비어 있지 않으면 `route_tables`의 모든 Route Table에 `aws_vpc_endpoint_route_table_association`으로 연결한다. 키는 `<service>/<rt_key>`다. 경로는 AWS가 prefix list로 넣으므로 `aws_route`를 만들지 않으며 RSC-RT-04, RSC-RT-08은 적용되지 않는다. |
| RSC-RT-07 | Peering 경로는 `peer_vpcs.<key>.route_tables`에 나열된 Route Table에, `peer_vpcs.<key>.remote_cidrs`의 CIDR마다 추가한다. |
| RSC-RT-08 | 모든 `aws_route`에 `timeouts.create = "5m"`를 둔다. |
| RSC-RT-09 | Association 키는 서브넷 키와 같다. AZ 그룹의 `route_table` 참조를 바꾸면 서브넷은 재생성되지 않고 Association만 교체된다. |
| RSC-RT-10 | `stack`이 지정된 Route Table은 그 스택의 태그를 가지며 스택 제거 시 NAT와 함께 삭제된다. 지정하지 않으면 Shared Network 리소스다. Route Table 키 변경은 RT와 NAT의 재생성으로 간주하고 변수 설명에 명시한다. |

### 3.7 Network ACL

| ID | 요구사항 |
| --- | --- |
| RSC-NACL-01 | 전용 NACL은 스택당 1개인 `stack_subnets.<stack>.nacl` 또는 `public_subnets_nacl`로 정의한다. 스택 NACL은 그 스택의 모든 Role 서브넷을 하나의 NACL에 연결하며, Role별 NACL은 두지 않는다. 정의하지 않은 서브넷은 기본 NACL(RSC-DEF-03)에 연결된다. |
| RSC-NACL-02 | 룰은 `ingress`, `egress` 각각 룰 이름을 키로 하는 Map이다. 값은 `rule_number`, `action`, `protocol`(필수), `from_port`, `to_port`, `cidr_block`, `ipv6_cidr_block`, `icmp_type`, `icmp_code`(선택). |
| RSC-NACL-03 | 같은 NACL·방향 안에서 `rule_number` 중복은 plan 실패. |
| RSC-NACL-04 | 룰 추가·삭제는 해당 룰만 생성·삭제하고 다른 룰을 재생성하지 않는다. |

### 3.8 기본 리소스 관리 (Default SG, RT, NACL, DHCP)

VPC가 자동으로 만드는 기본 Security Group, 기본 Route Table, 기본 Network ACL은 항상 모듈이 채택해 이름과 태그를 부여한다. 채택 여부를 정하는 입력을 두지 않는다.

| ID | 요구사항 |
| --- | --- |
| RSC-DEF-01 | 기본 Security Group은 인바운드·아웃바운드 룰을 모두 비워 전면 차단한다. 룰을 추가하는 입력을 제공하지 않으며 워크로드는 전용 SG를 써야 한다. 이 동작은 **조직 보안 기준선으로 확정**(2026-09-10)되었다. |
| RSC-DEF-02 | 기본 Route Table은 경로 없이 채택하고 어떤 서브넷도 연결하지 않는다. |
| RSC-DEF-03 | 기본 Network ACL은 AWS 기본 허용 룰(IPv4·IPv6 전체 허용) 그대로 채택한다. 전용 NACL이 없는 서브넷이 연결되며(AWS 기본 동작) 룰을 바꾸는 입력을 두지 않는다. |
| RSC-DEF-04 | DHCP Options는 `dhcp_options` 객체가 `null`이 아닐 때만 생성·연결한다. 필드와 기본값: `domain_name`(선택, 생략 시 `context.pri_domain`), `domain_name_servers`(기본 `["AmazonProvidedDNS"]`), `ntp_servers`(기본 빈 목록), `netbios_name_servers`(기본 빈 목록), `netbios_node_type`(선택). |
| RSC-DEF-05 | 계정 Default VPC 관리 기능은 이 모듈 범위에서 제외한다. |

### 3.9 VPC Endpoints (Shared Network Services)

| ID | 요구사항 |
| --- | --- |
| RSC-VPCE-01 | `vpc_endpoints.gateway`는 서비스 이름 집합(`s3`, `dynamodb`)이며 Gateway Endpoint를 만들고 RSC-RT-06에 따라 RT에 연결한다. |
| RSC-VPCE-02 | `vpc_endpoints.interface`는 서비스 이름을 키로 하는 Map이다. 값은 선택 `private_dns_enabled`(기본 `true`), 선택 `policy`, 선택 `security_group_ids`. |
| RSC-VPCE-03 | Interface Endpoint는 `shared_private_subnets`(RSC-PUB-07)의 모든 서브넷에 ENI를 만든다. `vpc_endpoints.interface`가 비어 있지 않은데 `shared_private_subnets`가 비어 있으면 plan 실패. |
| RSC-VPCE-04 | `security_group_ids`를 주지 않으면 모듈이 Endpoint 전용 SG 1개를 만들고 VPC CIDR과 보조 CIDR에서 443 인바운드만 허용한다. |
| RSC-VPCE-05 | Endpoint 추가·삭제는 다른 Endpoint와 RT에 영향을 주지 않는다. |
| RSC-VPCE-06 | Endpoint는 `Stack = shared-network`로 태깅한다. |

### 3.10 VPC Peering

REQ-101 7.1절을 리소스 수준으로 구체화한다.

| ID | 요구사항 |
| --- | --- |
| RSC-PCX-01 | `peer_vpcs`는 Peering 키를 가진 Map이며 최대 2개다. 3개 이상이면 plan 실패. |
| RSC-PCX-02 | 값은 `peer_vpc_id`, `peer_account_id`, `remote_cidrs`(집합), `route_tables`(경로를 추가할 `route_tables` 키 집합), 선택 `auto_accept`(기본 `false`), 선택 `tags`를 가진다. 상대 리전은 `context.region`으로 고정한다. |
| RSC-PCX-03 | 요청자 측 `aws_vpc_peering_connection`을 만들고, 수락은 상대 계정 책임이다. `auto_accept`는 같은 계정일 때만 허용하며 다른 계정에서 `true`이면 plan 실패. |
| RSC-PCX-04 | `remote_cidrs`는 VPC CIDR·보조 CIDR과 겹치면 plan 실패. `route_tables` 키 참조 검사는 2.4절을 따른다. |
| RSC-PCX-05 | 경로는 RSC-RT-07을 따른다. 상대 VPC 전체가 아니라 `remote_cidrs`만 라우팅한다. |
| RSC-PCX-06 | Peering 추가·삭제는 다른 Peering, 스택, RT 리소스에 변경을 만들지 않는다. |

### 3.11 VPN Gateway와 Customer Gateway

| ID | 요구사항 |
| --- | --- |
| RSC-VPN-01 | `vpn_gateway` 객체가 `null`이 아니면 VGW를 만든다. 값은 선택 `amazon_side_asn`(생략 시 `null`로 두어 AWS 기본값 `64512`가 적용된다), 선택 `availability_zone`(AZ 이름. 2.4절의 예외), `propagate_to`(전파할 Route Table 키 집합, 기본 `[]`). 모든 RT에 전파하려면 키를 모두 나열하며 와일드카드는 두지 않는다. |
| RSC-VPN-02 | `vpn_gateway.existing_id`가 있으면 새로 만들지 않고 attachment로 연결한다. `existing_id`와 함께 `amazon_side_asn` 또는 `availability_zone`을 `null`이 아닌 값으로 주면 plan 실패. |
| RSC-VPN-03 | 경로 전파는 `propagate_to`의 RT 키마다 1개의 propagation 리소스를 만들고 키는 RT 키와 같다. 키 참조 검사는 2.4절을 따른다. |
| RSC-VPN-04 | `customer_gateways`는 키 Map이며 값은 `bgp_asn`, `ip_address`(필수), 선택 `device_name`, 선택 `tags`. `type`은 `ipsec.1` 고정. |
| RSC-VPN-05 | VPN Connection 자체는 이 모듈 범위 밖이다. 출력 `vgw_id`, `cgw_ids`로 상위 모듈이 연결한다. |

### 3.12 VPC Flow Logs

| ID | 요구사항 |
| --- | --- |
| RSC-FLOW-01 | `flow_log` 객체가 `null`이 아니면 VPC 단위 Flow Log 1개를 만든다. |
| RSC-FLOW-02 | `destination_type`은 `s3` 또는 `cloud-watch-logs`. `s3`이면 `destination_arn` 필수. `cloud-watch-logs`이면 두 방식 중 하나를 택한다. 호출자가 만든 로그 그룹과 롤을 쓰면 `destination_arn`과 `iam_role_arn`을 모두 주고, `create_log_group = true`이면 모듈이 로그 그룹과 IAM 롤을 만들며 이때 `destination_arn`·`iam_role_arn`은 주지 않는다. 두 방식을 섞으면 plan 실패. |
| RSC-FLOW-03 | 모듈이 로그 그룹을 만들 때 `retention_in_days`(기본 `90`), 선택 `kms_key_id`를 적용하고, IAM 롤은 해당 로그 그룹에만 쓰기 권한을 가진다. |
| RSC-FLOW-04 | `traffic_type`은 `ACCEPT`, `REJECT`, `ALL`(기본 `ALL`). `max_aggregation_interval`은 `60` 또는 `600`(기본 `600`). 둘 다 validation. |
| RSC-FLOW-05 | S3 대상 옵션 `file_format`(`parquet` 기본, `plain-text`), `hive_compatible_partitions`(기본 `true`), `per_hour_partition`(기본 `true`)을 제공한다. |
| RSC-FLOW-06 | S3 버킷 정책은 모듈 범위 밖이며, 변수 설명에 `delivery.logs.amazonaws.com` 허용이 필요함을 명시한다. |
| RSC-FLOW-07 | 레코드 필드 정의는 `log_format`(선택, 기본 `null` = AWS 기본 포맷)으로 받아 `aws_flow_log.log_format`에 그대로 전달한다. |

### 3.13 Private DNS (Route53 Private Hosted Zone)

| ID | 요구사항 |
| --- | --- |
| RSC-DNS-01 | `private_dns` 객체가 `null`이 아니면 Private Hosted Zone 1개를 만들고 이 VPC에 연결한다. `domain_name`을 생략하면 `context.pri_domain`을 쓴다. |
| RSC-DNS-02 | `private_dns.additional_vpc_ids`로 같은 계정의 다른 VPC를 존에 연결할 수 있다. |
| RSC-DNS-03 | Interface Endpoint의 Private DNS(RSC-VPCE-02)와 이 존은 독립이다. 존 생성이 Endpoint DNS 동작에 영향을 주지 않는다. |

### 3.14 출력

| ID | 요구사항 |
| --- | --- |
| RSC-OUT-01 | 복수 리소스 출력은 리소스 키를 그대로 키로 갖는 Map으로 낸다. 예: `subnet_ids = { "web/private/app-a1" = "subnet-..." }`. 불필요한 목록 출력은 제공하지 않으며, 목록 출력은 `azs`처럼 입력 반영값에 한한다. |
| RSC-OUT-02 | 스택 단위 조회용으로 `stacks.<stack>.subnet_ids_by_role.<role>`(서브넷 이름 → ID Map) 구조를 낸다. |
| RSC-OUT-03 | Shared Public·Private 서브넷은 `shared_network` 객체로 낸다. NAT와 EIP는 `stack` 귀속이 가능하므로 `shared_network`에 넣지 않고 최상위 `nat_gateway_ids`, `nat_eip_allocation_ids`, `nat_public_ips`로 내며, `nat_public_ips`는 EIP 재사용 여부와 무관하게 RT 키 → 퍼블릭 IP Map이다. |
| RSC-OUT-04 | 단일 리소스 출력은 리소스가 없으면 `null`을 낸다. 빈 문자열을 쓰지 않는다. |
| RSC-OUT-05 | Peering, Endpoint, CGW 출력은 각 키 Map으로 낸다. |
| RSC-OUT-06 | 모듈은 아래 출력 표의 항목을 모두 제공한다. 항목을 추가할 수 있으나 삭제·개명은 MAJOR 변경으로 취급한다. |

출력 표:

| 출력 | 형식 | 내용 |
| --- | --- | --- |
| `vpc_id`, `vpc_arn`, `vpc_cidr_block`, `vpc_ipv6_cidr_block`, `vpc_owner_id` | 단일 | VPC 속성 |
| `vpc_secondary_cidr_association_ids` | CIDR → ID | 보조 CIDR 연관 |
| `igw_id`, `igw_arn`, `eigw_id` | 단일 | 게이트웨이 |
| `default_security_group_id`, `default_network_acl_id`, `default_route_table_id`, `dhcp_options_id` | 단일 | 기본 리소스 |
| `shared_network.public_subnet_ids`, `.public_subnet_arns`, `.public_subnet_cidr_blocks` | 서브넷 이름 → 값 | Shared Public Subnet |
| `shared_network.private_subnet_ids`, `.private_subnet_arns`, `.private_subnet_cidr_blocks` | 서브넷 이름 → 값 | Shared Private Subnet(정의 시) |
| `nat_gateway_ids`, `nat_eip_allocation_ids`, `nat_public_ips` | RT 키 → 값 | 모든 NAT와 EIP |
| `subnet_ids`, `subnet_arns`, `subnet_cidr_blocks`, `subnet_ipv6_cidr_blocks` | 서브넷 키 → 값 | 모든 스택 서브넷 |
| `route_table_ids` | RT 키 → ID | 모든 RT |
| `route_table_association_ids` | 서브넷 키 → ID | 연결 |
| `network_acl_ids`, `network_acl_arns` | NACL 키 → 값 | 전용 NACL |
| `stacks.<stack>.subnet_ids_by_role.<role>`, `.route_table_ids`, `.nat_gateway_ids`, `.db_subnet_group_names`, `.db_subnet_group_ids` | 서브넷 이름 또는 키 → 값 | 스택 단위 조회. RT·NAT는 `stack`이 그 스택인 항목. DB Subnet Group은 그룹 키 → 값 |
| `vpc_endpoint_ids`, `vpc_endpoint_dns_entries`, `vpc_endpoint_security_group_id` | 서비스 → 값, 단일 | Endpoint |
| `peering_connection_ids`, `peering_connection_status` | Peering 키 → 값 | Peering |
| `vgw_id`, `vgw_arn` | 단일 | VGW |
| `cgw_ids`, `cgw_arns` | CGW 키 → 값 | CGW |
| `flow_log_id`, `flow_log_destination_arn`, `flow_log_cloudwatch_log_group_arn`, `flow_log_cloudwatch_iam_role_arn` | 단일 | Flow Log |
| `private_zone_id`, `private_zone_name`, `private_zone_arn` | 단일 | Private Hosted Zone |
| `azs`, `name_prefix` | 목록, 단일 | 입력 반영값 |

## 4. 입력 변수 구조 요구사항

REQ-101 9절 입력 모델을 리소스별로 구체화한다. 이 표가 모듈 입력의 유일한 정의다. 복잡한 변환을 `locals`에서 하지 않고 입력 구조 자체가 리소스 인자에 그대로 대응되어야 한다.

아래 표에서 `AZ그룹`은 3.3절의 서브넷 AZ 그룹 객체 `map(object({ route_table, subnets = map(string), tags, ipv6_indexes }))`(AZ ID 키)를 뜻한다. `route_table`은 모든 그룹에서 필수다.

| 입력 | 타입 골격 | 대응 절 |
| --- | --- | --- |
| `context` | `object({ region, region_alias, project, environment, env_alias, owner, team, cost_center, name_prefix, pri_domain, tags })` 필수. tfmodule-context `v1.3.5` 출력 스키마와 동일 | 2.2, 2.3 |
| `vpc_cidr`, `secondary_cidrs`, `azs` | `string`(필수), `set(string)` 기본 `[]`, `list(string)`(필수, AZ ID) | 3.1, 3.2 |
| `enable_ipv6` | `bool`, 기본 `false` | RSC-VPC-05 |
| `public_subnets` | `AZ그룹`, 기본 `{}` | 3.3 |
| `public_subnets_nacl` | `object({ ingress = map(object({...})), egress = map(object({...})) })`, 기본 `null` | 3.7 |
| `shared_private_subnets` | `AZ그룹`, 기본 `{}` | 3.3, 3.9 |
| `route_tables` | `map(object({ default_route, nat_public_subnet, eip_allocation_id, stack, tags }))`, 기본 `{}` | 3.5, 3.6 |
| `stack_subnets` | `map(object({ db_subnet_groups = map(set(string)) 기본 {}, subnets = map(AZ그룹), nacl = object({ ingress, egress }) 기본 null, tags }))`, 기본 `{}`. `subnets`의 키는 Role, `db_subnet_groups`의 키는 그룹 이름이고 값은 서브넷 이름 집합 | 3.4, 3.7 |
| `vpc_endpoints` | `object({ gateway = set(string), interface = map(object({ private_dns_enabled, policy, security_group_ids })) })`, 기본 `null` | 3.9 |
| `peer_vpcs` | `map(object({ peer_vpc_id, peer_account_id, remote_cidrs, route_tables, auto_accept, tags }))`, 기본 `{}` | 3.10 |
| `vpn_gateway`, `customer_gateways` | `object({ amazon_side_asn, availability_zone, propagate_to, existing_id })` 기본 `null`, `map(object({ bgp_asn, ip_address, device_name, tags }))` 기본 `{}` | 3.11 |
| `flow_log` | `object({ destination_type, destination_arn, iam_role_arn, create_log_group, retention_in_days, kms_key_id, traffic_type, max_aggregation_interval, log_format, file_format, hive_compatible_partitions, per_hour_partition })`, 기본 `null` | 3.12 |
| `private_dns` | `object({ domain_name, additional_vpc_ids })`, 기본 `null` | 3.13 |
| `dhcp_options` | `object({ domain_name, domain_name_servers, ntp_servers, netbios_name_servers, netbios_node_type })`, 기본 `null` | 3.8 |
| `resource_tags` | `object({ vpc, igw, eigw, public_subnet, shared_private_subnet, stack_subnet, route_table, nat_gateway, eip, network_acl, db_subnet_group, default_security_group, default_route_table, default_network_acl, dhcp_options, vpc_endpoint, vpc_endpoint_security_group, peering, vpn_gateway, customer_gateway, flow_log, private_zone })` 각 필드 `map(string)` 선택 | 2.3 |
| `common_billing_tags`, `tags` | `map(string)`, 기본 `{}` | 2.3 |

- 모든 `object` 입력은 `optional()`로 선택 필드를 표현하고 기본값을 타입 정의에 둔다.
- 이 표에 없는 입력은 두지 않는다. 입력을 추가할 때는 이 표와 대응 절을 같은 변경에서 갱신한다. 스택의 성격이나 용도를 나타내는 입력(`type` 등)은 두지 않으며 태그로만 구별한다.
- 허용 값이 정해진 필드는 모두 `validation` 블록을 가진다: `route_tables.<key>.default_route`(`igw`·`nat`·`none`), `flow_log.destination_type`, `flow_log.traffic_type`, `flow_log.max_aggregation_interval`, `flow_log.file_format`, `vpc_endpoints.gateway`(`s3`·`dynamodb`), `dhcp_options.netbios_node_type`(`1`·`2`·`4`·`8`).

## 5. 완료 기준

REQ-101 10절에 더해 리소스 수준에서 다음을 만족해야 한다. 검증은 `terraform test`의 `command = plan` 테스트로 수행하며 실제 리소스를 생성하지 않는다.

- 스택 1개 추가 시 plan 결과가 그 스택 키의 리소스 생성만 포함한다.
- 스택 1개 제거 시 plan 결과가 그 스택 키의 리소스 삭제만 포함한다.
- `azs`에 AZ 1개 추가 시 기존 리소스 변경 0건.
- Route Table 수가 `route_tables` 항목 수와 같고, NAT 수가 `default_route = "nat"` 항목 수와 같으며, 각 NAT가 `nat_public_subnet`이 가리키는 서브넷에 있다.
- 모든 리소스의 `Name` 태그가 `<prefix>-<키>-<유형 접미어>`(2.2절)와 일치한다. 예: 서브넷 `blb-a1` → `<prefix>-blb-a1-sn`, RT `pri-a1` → `<prefix>-pri-a1-rt`, 그 NAT → `<prefix>-pri-a1-nat`.
- `default_route = "none"` RT에 `0.0.0.0/0` 경로가 없다. `intra` 서브넷은 항상 그런 RT에만 연결되어 있다.
- `database` 서브넷이 `nat` RT를 참조한 경우에만 그 서브넷 경로에 NAT가 있다.
- Peering 2개 정의 시 `route_tables`에 없는 RT에 Peering 경로가 없다.
- 모든 리소스의 `Stack`, `ResourceScope` 태그가 2.3절과 REQ-101 8.2절에 일치하고, 호출자가 AZ 그룹 `tags`에 정의한 태그가 그 그룹의 서브넷에 그대로 적용된다.
- 모든 출력이 키 Map 또는 `null` 가능 단일 값이며, 3.14절 출력 표의 항목이 모두 존재한다.
- 잘못된 입력(AZ 미포함, CIDR 겹침, 서브넷 이름 중복, 룰 번호 중복, 3개 이상 Peering, Cross-account `auto_accept`, `private` 없는 스택, `database` Role이 아니거나 다른 스택의 서브넷을 넣은 `db_subnet_groups`, 2개 AZ 미만인 DB Subnet Group, 스택 간 DB Subnet Group 이름 중복, 존재하지 않는 `route_table`·`nat_public_subnet` 참조, Role이 허용하지 않는 `default_route` 참조, 참조되지 않는 RT, `nat` 아닌 RT의 `nat_public_subnet`·`eip_allocation_id`, `igw` RT를 참조하지 않는 Public AZ 그룹, `azs` 1개, `shared_private_subnets` 없는 Interface Endpoint, VPC CIDR과 겹치는 `remote_cidrs`, `resource_tags`·커스텀 `tags`의 보호 키, `existing_id`와 함께 준 VGW 생성 옵션, 존재하지 않는 `propagate_to` 키, 이름 키 문자 규칙 위반)이 plan에서 실패한다. 이 목록은 본문 요구사항의 실패 조건 전체다.

## 6. 결정 사항

아래와 같이 확정했다. 본문의 관련 항목은 이 결정을 반영한 상태다.

| 일자 | 항목 | 결정 | 반영 위치 |
| --- | --- | --- | --- |
| 2026-09-10 | `context` 입력 | **필수**. tfmodule-context `v1.3.5` 출력을 받아 리소스 이름 접두어(`name_prefix`), 태그 병합 1단계(`tags`), 리전(`region`)의 공급원으로 쓴다. `vpc_name`, `region`, `peer_region` 입력을 두지 않는다 | 2.2, 2.3, 4절, RSC-PCX-02, RSC-DNS-01 |
| 2026-09-10 | Subnet Role | **4종 고정**. `public`, `private`, `database`, `intra`(REQ-101 3.1절). 파생 Role을 두지 않는다 | 3.4, RSC-SUB-02 |
| 2026-09-10 | 기본 SG·RT·NACL | **항상 채택**. 채택 여부·룰 입력을 두지 않는다. 기본 SG 전면 차단의 근거는 RSC-DEF-01 | 3.8 |
| 2026-09-10 | IPv6 | **선택 지원**. `enable_ipv6` 기본 `false` | RSC-VPC-05, RSC-PUB-06, RSC-RT-05 |
| 2026-09-10 | Shared Private Subnet | **Interface Endpoint ENI 전용**. Toolchain·Observability는 `stack_subnets`의 스택으로 정의한다 | RSC-PUB-07, RSC-VPCE-03 |
| 2026-09-10 | DNS 속성·테넌시 | **고정**. DNS 지원·호스트 이름 항상 활성, 테넌시 `default`. 입력을 두지 않는다 | RSC-VPC-04 |
| 2026-09-11 | Route Table·NAT 모델 | **명시 선언으로 전환**. NAT·RT 모드와 호환표를 제거하고 `route_tables`를 입력으로 선언한다. 서브넷 AZ 그룹은 `route_table` 키를 참조한다. 스택 `internet_egress` 플래그는 제거한다 | REQ-101 4·5절, 3.5, 3.6, 4절 |
| 2026-09-11 | `database` 인터넷 경로 | **옵션**. 기본은 `none`이며 OS 패치 등 외부 인터넷 리소스 접근이 필요하면 `nat` RT를 참조한다. `intra`는 `none` 고정 | REQ-101 3.1절, 3.4, RSC-SUB-04 |
| 2026-09-11 | 리소스 이름 규칙 | **호출자 키 기반**. 서브넷·RT는 호출자가 정한 이름을 키로 하고 `Name`은 `<prefix>-<키>-<유형 접미어>`다. 모듈이 스택·Role·AZ를 조합해 이름을 만들지 않는다 | REQ-101 9.1절, 2.1, 2.2 |
| 2026-09-11 | 서브넷 AZ 그룹 | **Role 안에서 AZ로 묶어 선언**. 그룹이 `route_table`을 한 번 적고 서브넷은 `이름 = CIDR`로 나열한다. 한 그룹에 서브넷 여러 개를 둘 수 있다. AZ는 AZ ID로 받는다 | REQ-101 3.1절, 2.4, 3.3, RSC-SUB-01, 4절 |
| 2026-09-11 | NAT 선언 위치 | **Route Table에 통합**. `nat` RT가 `nat_public_subnet`을 선언하면 그 RT 키로 NAT를 만든다. 별도 `nat_gateways` 입력을 두지 않고 NAT 공유 구성은 지원하지 않는다 | REQ-101 4절, 3.5, RSC-RT-01 |
| 2026-09-11 | DB Subnet Group | **스택 필드 `db_subnet_groups`로 멤버까지 선언**. 그룹 이름이 리소스 키이고 이름은 `<prefix>-<db_subnet_group>-sng`, 값은 넣을 서브넷 이름 집합이다. 스택당 여러 그룹을 둘 수 있고 나열하지 않은 `database` 서브넷은 그룹에 들어가지 않는다. `create_db_subnet_group` 불리언과 단일 문자열 안을 대체한다 | 2.1, 2.2, RSC-SUB-05, 3.14, 4절 |
| 2026-09-11 | Public IGW Route Table | **호출자가 선언**. 자동 생성·예약 키·필드 생략 같은 예외를 두지 않는다. 모든 RT는 `route_tables`에 선언하고 모든 AZ 그룹은 `route_table`을 적는다. NAT 위치는 `nat_public_subnet`으로 직접 지정한다. 입력과 리소스의 1:1 대응, 그룹 구조 일관성, 도출 로직 배제를 위해 자동 생성 안(2026-09-11 오전)을 철회한 결정이다 | REQ-101 5절, RSC-PUB-04, RSC-RT-01, RSC-RT-03 |
| 2026-09-11 | 스택 NACL | **스택당 1개**. `stack_subnets.<stack>.nacl` 하나가 그 스택의 모든 Role 서브넷에 연결된다. Role별 NACL(`nacl.<role>`)은 두지 않으며 NACL 키와 이름은 스택 키만 쓴다 | 2.1, 2.2, RSC-NACL-01, 4절 |
| 2026-09-11 | `SubnetRole` 태그 | **제거**. 모듈이 참조하거나 검증하는 곳이 없어 리소스 범위 태그는 `Stack`, `ResourceScope` 2개만 둔다 | REQ-101 8.1·8.2절, 5절 |
| 2026-09-11 | VGW `propagate_to` | **키 나열만 허용**. `["*"]` 와일드카드를 제거해 2.4절 참조 검사에 예외를 두지 않는다 | RSC-VPN-01, RSC-VPN-03 |
| 2026-09-11 | Gateway Endpoint 연결 | **association 리소스**. `aws_route`가 아니라 `aws_vpc_endpoint_route_table_association`으로 연결하고 키는 `<service>/<rt_key>` | 2.1, RSC-RT-06 |
| 2026-09-11 | 스택 `type`·자동 태그 | **제거**. 스택 성격 입력 `type`과 그로부터 만들던 `ServiceRole` 태그, EKS 자동 태그를 두지 않는다. 성격·컨트롤러 태그는 호출자가 AZ 그룹 `tags`에 직접 정의한다 | REQ-101 3.1·8절, 2.3, 4절, REQ-103 |

## 7. 참조

- 공통 전제: `requirements/REQ-101-TFMODULE-VPC-BASE.md`
- EKS 스택 서브넷 태그 안내: `requirements/REQ-103-TFMODULE-VPC-EKS.md`
