# REQUIREMENTS — 무엇을 만족해야 하는가

> **문서 종류:** Terraform 모듈 요구사항 명세
> **모듈:** `tfmodule-aws-vpc`
> **답하는 질문:** 이 모듈은 왜 존재하고, 무엇을 만들며, 어디까지 책임지는가.
> **함께 읽기:** [ARCHITECTURE](ARCHITECTURE.md) · [POLICIES](POLICIES.md) · [DECISIONS](DECISIONS.md)

---

## 1. 이 모듈은 무엇이고 왜 필요한가

여러 워크로드를 한 AWS 계정의 **Platform VPC** 하나에 올릴 때, 네트워크를 워크로드마다 손으로 설계하면 같은 조직 안에서도 서브넷 계층·라우팅·태그가 제각각이 된다. 새 워크로드를 붙일 때마다 기존 네트워크를 건드리게 되고, 그 변경이 다른 워크로드에 어떤 영향을 주는지 plan 만 보고는 알 수 없다.

이 모듈은 그 설계를 **선언형 입력 한 벌**로 고정한다. 호출자는 "어떤 스택이 어느 AZ에 어떤 대역을 쓰고 어디로 나가는가"만 적고, VPC·서브넷·라우팅·게이트웨이·엔드포인트·로그를 모듈이 같은 규칙으로 만든다.

핵심 목표는 다섯 가지다.

| 목표 | 뜻 |
| --- | --- |
| 워크로드 스택의 수평 확장 | 스택을 더해도 모듈 코드를 고치지 않는다. 입력에 항목 하나를 더한다 |
| 워크로드별 네트워크 수직 격리 | 스택마다 전용 서브넷 집합을 갖고 다른 스택과 공유하지 않는다 |
| Multi-AZ 기반 고가용성 | 최소 2개, 권장 3개 AZ에 배치한다 |
| Shared Service의 Private 접근 | Toolchain·Observability 같은 공유 서비스가 Public IP 없이 각 워크로드에 닿는다 |
| 안전한 추가·변경·제거 | 한 스택을 더하거나 빼도 다른 스택과 공유 네트워크의 plan 이 흔들리지 않는다 |

---

## 2. 추구하는 가치

이 모듈은 리소스를 만드는 Wrapper 가 아니라 조직의 네트워크 정책을 구현하는 계층이다. 다음 순서로 가치를 둔다.

| 가치 | 이 모듈에서의 의미 |
| --- | --- |
| **Consistency** | 같은 입력은 언제나 같은 리소스 키·이름·태그를 만든다. 이름은 `context.name_prefix` 에서, 태그는 `context.tags` 에서 파생한다 |
| **Predictability** | 입력 한 줄만 읽어도 그 서브넷이 어디에 놓이고 어디로 나가는지 드러난다. 모듈이 경로를 추론하지 않는다 |
| **Policy by Design** | 기본 SG 전면 차단, `map_public_ip_on_launch = false`, Endpoint SG 443 한정 같은 보안 기본값을 입력으로 끄지 못한다 |
| **Operational Simplicity** | 스택 추가·제거·경로 변경이 그 리소스에만 영향을 준다. 수명주기는 [POLICIES 7절](POLICIES.md#7-수명주기-정책)이 보장한다 |
| **Maintainability** | 모든 리소스가 `for_each` 와 호출자가 정한 이름 키로 만들어져 Terraform 주소가 순서에 흔들리지 않는다 |
| **Automation First** | 검증은 `validate`·`terraform test`·`plan` 으로 자동화하고, 잘못된 입력은 apply 가 아니라 plan 에서 실패시킨다 |

---

## 3. 설계 우선순위

설계·구현 의사결정이 충돌할 때 다음 순서를 적용한다. 기능 추가로 상위 원칙이 훼손되면 기능을 포기한다.

| 순위 | 원칙 | 이 모듈에서의 적용 예 |
| --- | --- | --- |
| 1 | 일관성 | Role 계층·모드 같은 분기를 두지 않고 모든 스택을 같은 구조로 표현한다 |
| 2 | 자동화 | 검사를 문서가 아니라 `validation`·`precondition` 으로 강제한다 |
| 3 | 안정성 | 리소스 키를 호출자 이름에서만 만들어 항목 증감이 다른 리소스를 재생성하지 않는다 |
| 4 | 보안 | 기본 리소스를 채택해 전면 차단 상태로 만들고, 위험한 기본값을 두지 않는다 |
| 5 | 운영성 | Flow Log·Private DNS·Endpoint 를 선언형으로 붙이고 출력으로 후속 모듈에 넘긴다 |
| 6 | 확장성 | 보조 CIDR·IPv6·다중 목적지 Flow Log 를 입력 추가만으로 지원한다 |
| 7 | 단순성 | `locals` 는 중첩 입력의 flatten 과 검사 계산에만 쓰고 값을 변환하지 않는다 |
| 8 | 비용 효율성 | NAT·Interface Endpoint 처럼 비싼 리소스를 암묵적으로 만들지 않는다([POLICIES 8절](POLICIES.md#8-비용-정책)) |

---

## 4. 책임 범위

### 4.1 이 모듈이 책임지는 것

```text
VPC 본체            VPC, 보조 CIDR, IPv6 /56, 기본 SG·RT·NACL 채택, DHCP Options
주소와 배치          서브넷(Shared Public / VPC Endpoint / 스택), AZ 배치, IPv6 /64 인덱스
경로                Route Table, 경로, Association, IGW, Egress-only IGW, VGW 전파
NAT                 NAT Gateway, EIP, NAT 인스턴스용 ENI와 Security Group
경계 통제            스택·Shared Public NACL, 모듈이 만든 ENI·Endpoint 에 붙는 SG
공유 서비스          Gateway·Interface VPC Endpoint, Endpoint 전용 SG, VPC Endpoint Subnet
데이터 계층          DB·ElastiCache·Redshift·MemoryDB Subnet Group
외부 연결            VGW, Customer Gateway
관측과 이름 해석      VPC Flow Log(목적지마다 1개), Route53 Private Hosted Zone
계약                이름·태그 표준 적용, 출력 제공
```

### 4.2 이 모듈이 책임지지 않는 것

| 영역 | 누가 하는가 | 근거 |
| --- | --- | --- |
| VPC Peering 연결·수락·경로 | [tfmodule-aws-vpc-peer](https://github.com/oniops/tfmodule-aws-vpc-peer/blob/main/README.md) | [ARCHITECTURE 5.2절](ARCHITECTURE.md#52-vpc-peering) |
| Transit Gateway 연결과 경로 | 연결을 만드는 전용 모듈 | 같음 |
| VPN Connection 자체 | 상위 모듈. 이 모듈은 `vgw_id`·`cgw_ids` 를 낸다 | RSC-VPN-05 |
| 워크로드 SG(EC2, ECS, EKS 노드, RDS) | 워크로드 모듈 | [ARCHITECTURE 5.1절](ARCHITECTURE.md#51-shared-service-private-access) |
| 인스턴스와 ENI 연결, AMI·인스턴스 타입 | 호출자 | RSC-ENI-08 |
| Flow Log 목적지 리소스(로그 그룹, 버킷, Delivery Stream)와 그 IAM 롤·버킷 정책·KMS 키 정책 | 그 리소스를 소유한 스택 | RSC-FLOW-08 |
| 계정 Default VPC 관리 | 범위 밖 | — |
| 조직 수준 IAM, CI/CD 파이프라인, 중앙 모니터링 플랫폼 | 범위 밖 | — |

경계를 정한 기준은 하나다. **연결의 양쪽 끝을 모두 아는 주체가 그 연결을 만든다.** Peering 은 두 VPC를 다 알아야 하므로 별도 모듈이고, 워크로드 SG 는 포트를 아는 워크로드 모듈의 몫이다.

---

## 5. 목표 요구사항

스캔용 요약이다. 각 행은 6절의 리소스 수준 요구사항 여럿에 대응하며, 수준은 RFC 2119 의 MUST / SHOULD / MAY 를 따른다. 정본은 6절이다.

| ID | 요구사항 | 수준 | 상세 |
| --- | --- | --- | --- |
| REQ-01 | 모듈 코드 변경 없이 선언형 입력만으로 워크로드 스택을 추가·제거할 수 있다 | MUST | RSC-SUB-10, [ARCHITECTURE 2.1](ARCHITECTURE.md#21-스택-모델) |
| REQ-02 | 각 스택은 다른 스택과 공유하지 않는 전용 서브넷 집합을 갖는다 | MUST | RSC-SUB-10, RSC-AZ-02 |
| REQ-03 | 서브넷은 최소 2개, 권장 3개의 서로 다른 AZ에 배치된다 | MUST | RSC-AZ-01, RSC-AZ-02 |
| REQ-04 | 한 스택을 추가·제거해도 다른 스택과 공유 네트워크 리소스에 변경·재생성이 생기지 않는다 | MUST | [POLICIES 7절](POLICIES.md#7-수명주기-정책) |
| REQ-05 | 모든 리소스 주소는 호출자가 정한 이름을 키로 하는 `for_each` 로 만든다 | MUST | [ARCHITECTURE 6절](ARCHITECTURE.md#6-리소스-키-체계) |
| REQ-06 | Route Table 과 경로는 호출자가 명시 선언하고 모듈이 도출하지 않는다 | MUST | RSC-RT-01~11 |
| REQ-07 | 경로 대상은 모듈 소유는 키로, 호출자 소유는 ID로 가리킨다 | MUST | RSC-RT-01, RSC-ENI-07 |
| REQ-08 | 외부 모듈이 이 모듈의 Route Table·Security Group 에 항목을 더해도 plan 이 흔들리지 않는다 | MUST | RSC-RT-02, RSC-SG-03 |
| REQ-09 | 모든 리소스 이름과 공통 태그는 `context` 에서 파생한다 | MUST | [ARCHITECTURE 7·10절](ARCHITECTURE.md#7-이름-규칙), [POLICIES 3·4절](POLICIES.md#3-이름-정책) |
| REQ-10 | 잘못된 입력 조합은 apply 가 아니라 plan 에서 실패한다 | MUST | [POLICIES 6절](POLICIES.md#6-입력-검증-정책) |
| REQ-11 | 조건 미달을 이유로 리소스를 조용히 0개 만들지 않는다 | MUST | [POLICIES 6.1](POLICIES.md#61-검증-원칙) |
| REQ-12 | 기본 SG·RT·NACL을 채택해 전면 차단·무경로 상태로 둔다 | MUST | RSC-DEF-01~03 |
| REQ-13 | 위험한 기본값을 두지 않는다(`map_public_ip_on_launch`는 `false` 고정) | MUST | RSC-PUB-01 |
| REQ-14 | 비용이 큰 선택 리소스를 암묵적으로 만들지 않는다 | MUST | [POLICIES 8절](POLICIES.md#8-비용-정책) |
| REQ-15 | 출력은 다른 모듈과의 계약이며 삭제·개명은 MAJOR 로 취급한다 | MUST | RSC-OUT-06, [POLICIES 10절](POLICIES.md#10-버전과-호환성) |
| REQ-16 | 보조 CIDR 추가로 IP 확장에 대응할 수 있다 | MUST | RSC-VPC-02, RSC-VPC-03 |
| REQ-17 | Shared Service 스택이 Public IP 없이 워크로드와 통신할 수 있다 | MUST | [ARCHITECTURE 5.1절](ARCHITECTURE.md#51-shared-service-private-access) |
| REQ-18 | Site-to-Site VPN 을 위한 VGW 1개와 여러 CGW 를 선언형으로 지원한다 | MUST | RSC-VPN-01~05 |
| REQ-19 | `mock_provider` 기반 `terraform test` 로 자격 증명 없이 검증할 수 있다 | MUST | [POLICIES 9절](POLICIES.md#9-검증과-테스트) |
| REQ-20 | IPv6 를 선택적으로 지원하고, 끄면 관련 리소스가 0개다 | SHOULD | RSC-VPC-05, RSC-RT-05 |
| REQ-21 | Production 구성으로 AZ마다 NAT 1개를 권장하되 공유 구성도 허용한다 | SHOULD | RSC-NAT-06, RSC-NAT-08 |
| REQ-22 | NAT Gateway 대신 NAT 인스턴스·어플라이언스 구성을 지원한다 | MAY | RSC-NAT-07, RSC-ENI-01~11 |
| REQ-23 | VPC Flow Log 를 여러 목적지에 동시에 보낼 수 있다 | MAY | RSC-FLOW-01~08 |
| REQ-24 | EKS 컨트롤러가 요구하는 서브넷 태그를 호출자가 붙일 수 있다 | MAY | [ARCHITECTURE 11절](ARCHITECTURE.md#11-eks-스택) |

---

## 6. 리소스별 요구사항

5절 목표를 리소스 수준에서 확정한 정본이다. ID 는 `RSC-<영역>-<번호>` 이며 코드 주석과 테스트가 이 ID를 가리킨다. 삭제된 ID는 재사용하지 않고 삭제 사실은 [DECISIONS](DECISIONS.md)에 남긴다. 별도 표기가 없는 행은 모두 MUST다.

각 행이 전제하는 공통 규칙은 다른 문서가 정의한다. 키 체계·이름·입출력 구조는 [ARCHITECTURE](ARCHITECTURE.md), 태그 병합·검사 배치·수명주기는 [POLICIES](POLICIES.md), 결정 배경은 [DECISIONS](DECISIONS.md)다.

### 6.1 VPC 본체

| ID | 요구사항 |
| --- | --- |
| RSC-VPC-01 | `vpc_cidr` 1개를 필수 입력으로 받는다. 기본값을 두지 않는다. |
| RSC-VPC-02 | `secondary_cidrs`는 CIDR 문자열을 키로 하는 집합으로 받아 항목별 `aws_vpc_ipv4_cidr_block_association`을 만든다. |
| RSC-VPC-03 | 보조 CIDR 항목과 그 대역의 서브넷을 함께 제거하면 apply가 순서 오류 없이 끝나야 한다. 서브넷이 남아 있는 상태에서 보조 CIDR 연관만 먼저 삭제되지 않는다. |
| RSC-VPC-04 | DNS 지원과 DNS 호스트 이름은 항상 활성이다. 끄는 입력을 두지 않는다. 인스턴스 테넌시는 `default`로 고정한다. |
| RSC-VPC-05 | IPv6는 `enable_ipv6`(기본 `false`)로 **선택적으로 지원**한다. 켜면 Amazon 제공 /56을 할당하고, 서브넷별 IPv6 /64 인덱스는 서브넷 항목의 `ipv6_index`로 받는다(ARCHITECTURE 2.3절). 값이 있는 서브넷은 IPv6 CIDR을 갖고 `assign_ipv6_address_on_creation = true`로 만들며, `null`인 서브넷은 IPv6 CIDR을 할당하지 않는다. 인덱스는 `0`~`255`(/56 안의 /64 개수)이며, VPC 안에서 인덱스가 중복되거나 범위를 벗어나면 plan 실패. IPv6가 꺼져 있으면 모듈이 만드는 IPv6 관련 리소스·경로가 0개다. 단 AWS가 기본 NACL에 두는 IPv6 전체 허용 룰은 모듈이 만드는 리소스가 아니므로 예외다(RSC-DEF-03). `enable_ipv6 = false`인데 `ipv6_index`가 `null`이 아닌 서브넷이 있으면 plan 실패. |

### 6.2 가용 영역

AZ 목록 입력(`azs`)은 두지 않는다. AZ는 서브넷 항목의 `az` 필드로만 선언한다(ARCHITECTURE 2.3절).

| ID | 요구사항 |
| --- | --- |
| RSC-AZ-01 | 모든 서브넷 항목의 `az` 값은 AZ ID 형식(`apne2-az1`처럼 `-az<번호>`로 끝나는 값)이어야 한다. 형식이 다르면 plan 실패. |
| RSC-AZ-02 | `shared_public.subnets`, `vpc_endpoint_subnets`, 모든 스택 서브넷의 `az` 값을 합쳐 서로 다른 AZ ID가 2개 미만이면 plan 실패(ARCHITECTURE 2.1절). |

### 6.3 Shared Public Network (Public Subnet, Internet Gateway)

| ID | 요구사항 |
| --- | --- |
| RSC-PUB-01 | `shared_public`(선택, 기본 `null`)은 `tags`, `nacl`, `subnets` 세 필드를 가진다. `subnets`는 ARCHITECTURE 2.3절의 서브넷 Map이며 1개 이상이어야 한다. `tags`는 그 아래 모든 서브넷과 Shared Public NACL에 적용되고, `nacl`은 RSC-NACL-01의 Shared Public NACL 입력이다. Public Subnet의 `map_public_ip_on_launch`는 `false`로 고정하고 입력을 두지 않는다. 퍼블릭 IP가 필요한 LB·NAT는 자체 EIP 또는 AWS 관리 IP를 쓴다. |
| RSC-PUB-02 | Shared Public Subnet은 모든 스택이 NAT·Public LB 배치에 공용으로 쓴다. NAT를 배치할 수 있는 서브넷은 여기뿐이다(RSC-NAT-02). |
| RSC-PUB-03 | 스택 전용 Public Subnet은 별도 입력이 아니다(ARCHITECTURE 2.2절). 스택 서브넷이 `gateway = "igw"`인 `0.0.0.0/0` 경로를 가진 Route Table을 `route_table`로 가리키면 그것이 스택 전용 Public Subnet이며, 스택 태그가 적용되고 `map_public_ip_on_launch`는 RSC-PUB-01과 같다. 모듈은 이 조합을 검사하지도 막지도 않는다. |
| RSC-PUB-04 | `shared_public.subnets`의 모든 서브넷은 `gateway = "igw"`인 `0.0.0.0/0` 경로를 가진 Route Table을 가리켜야 한다. 아니면 plan 실패(검사 위치는 POLICIES 6.1절). IGW Route Table은 호출자가 `route_tables`에 선언하며 모듈이 자동으로 만들지 않는다. |
| RSC-PUB-05 | Internet Gateway는 `gateway = "igw"`인 경로가 1개 이상일 때 1개 만들고, 없으면 만들지 않는다. 별도 입력을 두지 않는다. Shared Public Subnet은 RSC-PUB-04로 그런 Route Table을 가리키므로 Shared Public Subnet이 있으면 IGW도 있다. Egress-only IGW의 생성 조건은 RSC-RT-05다. |

### 6.4 Workload Stack Subnet Set

스택 서브넷은 `stack_subnets.<stack>.subnets.<name>`으로 정의한다. 스택 하나가 서브넷 평면 Map, DB·ElastiCache Subnet Group, 선택 NACL, 스택 `tags`를 담는다. 서브넷 모델과 Role 계층 부재는 ARCHITECTURE 2.2절을, 서브넷 객체 구조는 ARCHITECTURE 2.3절을 따르며 여기서 다시 정의하지 않는다.

| ID | 요구사항 |
| --- | --- |
| RSC-SUB-05 | 스택의 `db_subnet_group`은 그룹 이름을 키로 하고 서브넷 이름 집합을 값으로 하는 Map(선택, 기본 `{}`)이다. 항목마다 `aws_db_subnet_group` 1개를 만들고 나열한 서브넷만 넣는다. 이름은 `<prefix>-<db_subnet_group>-sng`. 나열하지 않은 서브넷은 어느 그룹에도 속하지 않는다. 다음이면 plan 실패: 멤버가 같은 스택의 서브넷이 아닐 때, 멤버가 2개 AZ 미만일 때(AWS 제약), 그룹 이름이 다른 스택의 DB 그룹 이름과 겹칠 때. 멤버 서브넷이 어떤 Route Table을 가리키는지는 검사하지 않는다. |
| RSC-SUB-09 | 스택의 `elasticache_subnet_group`은 RSC-SUB-05와 같은 구조이며 항목마다 `aws_elasticache_subnet_group` 1개를 만든다. 이름은 `<prefix>-<elasticache_subnet_group>-ecsng`. 다음이면 plan 실패: 멤버가 같은 스택의 서브넷이 아닐 때, 멤버가 1개 미만일 때, 그룹 이름이 다른 스택의 ElastiCache 그룹 이름과 겹칠 때. |
| RSC-SUB-11 | 스택의 `redshift_subnet_group`은 RSC-SUB-05와 같은 구조이며 항목마다 `aws_redshift_subnet_group` 1개를 만든다. 이름은 `<prefix>-<redshift_subnet_group>-rssng`. 다음이면 plan 실패: 멤버가 같은 스택의 서브넷이 아닐 때, 멤버가 1개 미만일 때, 그룹 이름이 다른 스택의 Redshift 그룹 이름과 겹칠 때. AWS는 서브넷 1개도 받으므로 모듈은 1개 이상만 검사하며, Multi-AZ 클러스터에는 2개 AZ 이상이 필요하다는 점을 변수 설명에 적는다. Redshift는 이름을 소문자로만 받고 255자로 제한하지만 모듈은 최종 이름의 길이를 검사하지 않는다(ARCHITECTURE 7절). |
| RSC-SUB-12 | 스택의 `memorydb_subnet_group`은 RSC-SUB-05와 같은 구조이며 항목마다 `aws_memorydb_subnet_group` 1개를 만든다. 이름은 `<prefix>-<memorydb_subnet_group>-mdsng`. 다음이면 plan 실패: 멤버가 같은 스택의 서브넷이 아닐 때, 멤버가 1개 미만일 때, 그룹 이름이 다른 스택의 MemoryDB 그룹 이름과 겹칠 때. Redshift와 같은 이유로 멤버 수는 1개 이상만 검사한다. MemoryDB 이름은 소문자·숫자·하이픈만 받고 255자로 제한되며, 길이 검사는 하지 않는다(ARCHITECTURE 7절). |
| RSC-SUB-13 | 네 종류의 Subnet Group은 서로 독립이다. 같은 서브넷이 여러 유형의 그룹에 동시에 속할 수 있고, 유형이 다르면 그룹 이름이 같아도 이름 접미어(`-sng`, `-ecsng`, `-rssng`, `-mdsng`)가 달라 리소스 이름이 겹치지 않으므로 허용한다. 이름 중복 검사는 같은 유형 안에서만 한다. |
| RSC-SUB-10 | 스택 `subnets`는 서브넷 이름을 키로 하는 ARCHITECTURE 2.3절 서브넷 객체의 Map이며 1개 이상이어야 한다. 비어 있으면 plan 실패. |

### 6.5 NAT Gateway와 EIP

NAT 정책 원칙은 ARCHITECTURE 4절을 따른다.

| ID | 요구사항 |
| --- | --- |
| RSC-NAT-01 | `nat_gateways`(선택, 기본 `{}`)는 호출자가 정한 키의 Map이다. 값은 `public_subnet`(필수), 선택 `eip_allocation_id`, 선택 `tags`(기본 `{}`)를 가진다. 항목마다 NAT 1개를 그 키로 만들어 `public_subnet`이 가리키는 Shared Public Subnet에 배치하고(`connectivity_type`은 `public` 고정이며 Private NAT Gateway는 모듈 범위 밖이다), `eip_allocation_id`가 없으면 같은 키의 EIP 1개를 함께 만든다(RSC-NAT-03). 어떤 경로도 참조하지 않는 항목도 선언된 대로 만든다(RSC-RT-03과 같은 원칙). |
| RSC-NAT-02 | `public_subnet`은 `shared_public.subnets`에 있는 서브넷 이름이어야 한다. 스택 서브넷(`<stack>/<name>`)은 지정할 수 없다. 둘 중 하나라도 위반하면 plan 실패. |
| RSC-NAT-03 | 항목에 `eip_allocation_id`가 있으면 EIP를 만들지 않고 그 allocation을 연결한다. `nat_public_ips` 출력은 EIP 재사용 여부와 무관하게 NAT 리소스의 `public_ip` 속성으로 낸다(ARCHITECTURE 9절). |
| RSC-NAT-06 | 어떤 NAT를 가리키는 경로를 가진 Route Table에 연결된 서브넷의 AZ가 그 NAT의 `public_subnet` AZ와 다르면 Cross-AZ 경로가 된다. 모듈은 이를 허용하되 변수 설명에 비용·장애 영향을 명시한다. |
| RSC-NAT-07 | NAT Gateway 대신 NAT 인스턴스·어플라이언스를 쓰는 구성에서는 `nat_gateways`를 비우고 경로가 ENI를 가리킨다(RSC-RT-01). ENI는 두 방법 중 하나로 정한다. (a) `eni_interfaces`로 모듈이 만들고 경로가 `eni` 키를 적는다(6.6절). 이때 ENI의 서브넷·사설 IP·`source_dest_check`·Security Group은 모듈 입력이다. (b) 호출자가 만든 ENI를 경로가 `network_interface_id`로 가리킨다. 이때 그 ENI가 어느 서브넷에 있는지 모듈이 검사하지 않는다. 어느 방법이든 인스턴스 자체(AMI, 인스턴스 타입, EIP)와 ENI 연결은 이 모듈 범위 밖이다. |
| RSC-NAT-08 | 한 NAT를 여러 Route Table의 경로가 참조할 수 있다. 여러 AZ가 NAT 1개를 공유하려면 각 Route Table의 경로가 같은 `nat_gateway` 키를 적는다. |

### 6.6 Network Interface (ENI)와 Security Group

모듈은 서브넷에 ENI를 만들어 Route Table 경로의 대상으로 쓸 수 있게 하고, 그 ENI에 붙일 Security Group과 그 룰도 만든다. NAT 인스턴스·어플라이언스처럼 호출자가 만드는 인스턴스에 붙일 ENI를 모듈이 먼저 만들어 두면, 인스턴스를 교체해도 경로 대상과 사설 IP, Security Group이 그대로 남는다. 인스턴스와 ENI의 연결만 이 모듈 범위 밖이다(RSC-ENI-08).

| ID | 요구사항 |
| --- | --- |
| RSC-ENI-01 | `eni_interfaces`(선택, 기본 `{}`)는 호출자가 정한 키의 Map이다. 값은 `subnet`(필수), 선택 `private_ips`(`set(string)`), 선택 `security_group_names`(`set(string)`, `security_groups`의 키), 선택 `security_group_ids`(`set(string)`, 호출자가 만든 SG ID), 선택 `source_dest_check`(`bool`, 기본 `true`), 선택 `interface_type`, 선택 `description`, 선택 `tags`(기본 `{}`)를 가진다. 항목마다 `aws_network_interface` 1개를 그 키로 만들며, 어떤 경로도 참조하지 않는 항목도 선언된 대로 만든다(RSC-RT-03과 같은 원칙). |
| RSC-ENI-02 | `subnet`은 이 모듈이 만드는 서브넷의 이름이다(`shared_public.subnets`, `vpc_endpoint_subnets`, 모든 스택 서브넷). 그 서브넷의 ID가 `subnet_id`가 되므로 ENI는 서브넷 생성 뒤에 만들어진다. 존재하지 않는 이름이면 plan 실패(검사 위치는 POLICIES 6.1절). |
| RSC-ENI-03 | `private_ips`가 `null`이면 AWS가 서브넷 대역에서 자동 할당한다. 값을 주면 `private_ips`에 그대로 전달하며, 서브넷 대역 밖이거나 이미 쓰는 주소면 AWS가 apply에서 거부한다. 모듈은 주소 대역을 검사하지 않는다(RSC-NAT-07과 같은 원칙). |
| RSC-ENI-04 | `source_dest_check`는 기본 `true`다. NAT 인스턴스·어플라이언스용 ENI는 호출자가 `false`로 줘야 하며, `true`인 ENI를 경로 대상으로 쓰면 그 ENI를 지나는 전달 트래픽이 버려진다. 변수 설명에 명시한다. |
| RSC-ENI-05 | ENI에 붙는 Security Group은 `security_group_names`(모듈이 만든 SG의 키)와 `security_group_ids`(호출자가 만든 SG의 ID)의 합집합이며, `aws_network_interface.security_groups`에 그대로 전달한다. 모듈 소유 대상은 키로, 호출자 소유 대상은 ID로 가리키는 원칙을 따른다(RSC-ENI-07과 같다). 둘 다 비어 있으면 `security_groups` 인자를 넘기지 않으며(빈 집합을 넘기지 않는다) AWS가 VPC 기본 SG를 붙인다. 기본 SG는 전면 차단이므로(RSC-DEF-01) 통신이 필요한 ENI는 둘 중 하나를 준다. 변수 설명에 명시한다. |
| RSC-ENI-06 | `interface_type`은 `null`(기본, ENA), `efa`, `efa-only` 중 하나다. AWS 인자 값을 그대로 받고 별칭을 두지 않으며 허용 값 밖이면 plan 실패. AWS가 허용하는 `branch`·`trunk`는 ECS·EKS의 ENI 트렁킹이 쓰는 값이라 컨트롤러가 직접 만들며 이 모듈의 대상이 아니다. 필요해지면 그때 허용 값을 넓힌다. |
| RSC-ENI-07 | 경로가 이 ENI를 가리키는 방법은 `routes`의 `eni`(이 Map의 키)다. 호출자가 만든 ENI는 `network_interface_id`(ID)로 가리키며 둘은 같은 경로 객체에서 택일이다(RSC-RT-01). |
| RSC-ENI-08 | 인스턴스 연결·해제는 모듈 범위 밖이다. 호출자가 출력 `eni_ids`로 `aws_network_interface_attachment`를 만들거나 인스턴스의 `network_interface` 블록에서 참조한다. 인스턴스에 연결된 ENI는 연결을 끊어야 삭제되므로 `eni_interfaces` 항목 제거는 호출자가 연결을 끊은 뒤에 한다. |
| RSC-ENI-09 | ENI가 인스턴스에 연결되기 전에는 그 ENI를 가리키는 경로로 트래픽이 흐르지 않는다. 모듈의 검증은 plan까지이므로(POLICIES 9.1절) 이 상태는 plan에서 드러나지 않으며, 호출자가 ENI를 연결한 뒤 경로 상태를 확인한다. |
| RSC-ENI-10 | IPv6 주소 옵션(`ipv6_addresses`, `ipv6_address_count` 등), `private_ip_list`, `attachment` 블록, `ena_srd_specification`은 입력에 두지 않는다. 필요하면 호출자가 자기 스택에서 ENI를 만들고 경로에서 `network_interface_id`로 가리킨다. |
| RSC-ENI-11 | `interface_type`이 `efa-only`인 ENI는 IP 트래픽을 다루지 않으므로 경로 대상이나 사설 IP 부여 대상이 아니다. 모듈은 조합을 검사하지 않으며 AWS가 apply에서 거부한다. NAT 용도의 ENI는 `interface_type`을 `null`(ENA)로 둔다. |

Security Group 요구사항은 다음과 같다. 이 절의 SG는 이 모듈이 만드는 ENI에 붙이는 용도이며, 워크로드 SG는 워크로드 모듈이 만든다(ARCHITECTURE 5.1절).

| ID | 요구사항 |
| --- | --- |
| RSC-SG-01 | `security_groups`(선택, 기본 `{}`)는 호출자가 정한 키의 Map이다. 값은 선택 `description`, 선택 `ingress`·`egress`(각각 룰 이름을 키로 하는 Map, 기본 `{}`), 선택 `tags`(기본 `{}`)를 가진다. 항목마다 `aws_security_group` 1개를 그 키로 만들어 이 VPC에 붙이며, 어떤 ENI도 참조하지 않는 항목도 선언된 대로 만든다(RSC-RT-03과 같은 원칙). 이름은 ARCHITECTURE 7절 표의 `<prefix>-<sg_key>-sg`이며 리소스 `name` 인자와 `Name` 태그에 모두 쓴다. `description`이 `null`이면 provider 기본값이 적용되고, 생성 후 `description`을 바꾸면 SG가 재생성된다(POLICIES 7절). |
| RSC-SG-02 | SG 이름은 VPC 안에서 유일해야 한다. `vpce`는 예약 키다(ARCHITECTURE 7절). |
| RSC-SG-03 | 룰은 `aws_security_group`의 인라인 `ingress`·`egress` 블록이 아니라 `aws_vpc_security_group_ingress_rule`·`aws_vpc_security_group_egress_rule` 리소스로 룰 하나당 1개씩 만든다. 키는 `<sg_key>/<direction>/<rule_name>`이다(ARCHITECTURE 6절). 인라인 블록을 쓰지 않으므로 호출자나 다른 모듈이 같은 SG에 룰을 더해도 이 모듈의 plan에 변경이 생기지 않는다(RSC-RT-02와 같은 원칙). |
| RSC-SG-04 | 룰 값은 `ip_protocol`(필수), 선택 `from_port`·`to_port`, 선택 `cidr_ipv4`·`cidr_ipv6`·`prefix_list_id`·`referenced_security_group_name`·`referenced_security_group_id`, 선택 `description`이다. `ip_protocol` 허용 값과 포트·ICMP 규칙은 ARCHITECTURE 8.3절을 따른다. 소스 다섯 필드 중 정확히 하나만 `null`이 아니어야 하며, `referenced_security_group_name`은 `security_groups`의 키(모듈 SG), `referenced_security_group_id`는 호출자가 만든 SG의 ID다. 다음이면 plan 실패: 소스 필드가 모두 `null`이거나 둘 이상이 `null`이 아닐 때, `referenced_security_group_name`이 `security_groups`에 없을 때, ARCHITECTURE 8.3절 규칙을 어길 때. |
| RSC-SG-05 | `ingress`나 `egress`가 비어 있으면 그 방향은 룰이 없어 전부 차단된다. AWS가 새 SG에 두는 아웃바운드 전체 허용 룰은 provider가 생성 시점에 회수하므로, 아웃바운드가 필요하면 `egress`에 룰을 적어야 한다. 변수 설명에 명시한다. |
| RSC-SG-06 | 룰 리소스의 태그는 그 SG의 태그(모듈 공통 `tags`, SG `tags`)를 따르며 `Name`은 붙이지 않는다(ARCHITECTURE 7절의 `Name`을 갖지 않는 리소스). |
| RSC-SG-07 | 포트 수준 접근 정책의 설계는 호출자의 몫이다. 모듈은 기본 룰 골격을 제공하지 않으며, 참고 예시는 README의 "Shared Service 접근 정책 예시" 절에 둔다(RSC-NACL-01과 같다). Endpoint 전용 SG는 RSC-VPCE-04가 따로 정한다. |

### 6.7 Route Table, Route, Association

Route Table 정책 원칙은 ARCHITECTURE 3절을 따른다.

| ID | 요구사항 |
| --- | --- |
| RSC-RT-01 | `route_tables`는 호출자가 정한 키의 Map이다. 값은 선택 `routes`(기본 `{}`), 선택 `propagate_vgw`(`bool`, 기본 `false`), 선택 `tags`(기본 `{}`)를 가진다. `routes`의 키는 목적지 CIDR(IPv4 또는 IPv6)이고 값은 `gateway`, `nat_gateway`, `eni`, `network_interface_id` 네 필드를 가진 객체로, 넷 중 정확히 하나만 `null`이 아니어야 한다. `gateway`는 `igw`·`eigw`·`vgw` 중 하나(validation), `nat_gateway`는 `nat_gateways`의 키, `eni`는 `eni_interfaces`의 키(6.6절), `network_interface_id`는 호출자가 만든 ENI ID(`eni-` 접두어, validation)다. 다음이면 plan 실패: 네 필드가 모두 `null`이거나 둘 이상이 `null`이 아닐 때, `gateway` 값이 허용 값 밖일 때, 목적지가 `vpc_cidr`이나 `secondary_cidrs`와 같을 때(`local` 경로는 AWS가 둔다), `gateway = "vgw"`이거나 `propagate_vgw = true`인데 `vpn_gateway`가 `null`일 때, `gateway = "eigw"`인데 목적지가 IPv4일 때, IPv6 목적지이거나 `gateway = "eigw"`인데 `enable_ipv6 = false`일 때. 검사 위치는 POLICIES 6.1절. |
| RSC-RT-02 | `routes`의 항목마다 `aws_route` 1개를 만들고 대상 필드를 그대로 전달한다(`gateway_id`, `egress_only_gateway_id`, `nat_gateway_id`, `network_interface_id`). `eni`와 `network_interface_id`는 같은 `network_interface_id` 인자로 들어가며, `eni`는 그 키의 ENI ID로 치환한다. `routes`에 없는 경로는 만들지 않는다. 모든 경로는 `aws_route` 리소스로 만들고 `aws_route_table`의 인라인 `route` 블록을 쓰지 않아, 외부 모듈(tfmodule-aws-vpc-peer 등)이 이 RT에 경로를 추가해도 이 모듈의 plan에 변경이 생기지 않는다. |
| RSC-RT-03 | 어떤 서브넷도 가리키지 않는 Route Table도 선언된 대로(경로 포함) 만들며 plan 실패나 경고로 다루지 않는다. 미참조 RT 제거는 호출자가 별도 변경으로 한다. |
| RSC-RT-04 | 경로 리소스 키는 `<rt_key>/<destination>`이다. 목적지가 `routes`의 Map 키이므로 같은 RT에 같은 목적지를 두 번 적는 것은 문법적으로 불가능하다. |
| RSC-RT-05 | IPv6 경로는 호출자가 `routes`에 `::/0` 같은 IPv6 목적지로 직접 적으며, 모듈이 IPv4 경로에서 도출하지 않는다. Egress-only IGW는 `gateway = "eigw"`인 경로가 1개 이상일 때 1개 만들고, 그 외에는 만들지 않는다. 별도 입력을 두지 않는다. IPv6 목적지와 `eigw` 대상은 `enable_ipv6 = true`일 때만 허용한다(RSC-RT-01). |
| RSC-RT-06 | Gateway Endpoint(S3, DynamoDB)는 `vpc_endpoints.gateway`가 비어 있지 않으면 `route_tables`의 모든 Route Table에 `aws_vpc_endpoint_route_table_association`으로 연결한다. 키는 `<service>/<rt_key>`다. 경로는 AWS가 prefix list로 넣으므로 `aws_route`를 만들지 않으며 RSC-RT-04, RSC-RT-08은 적용되지 않는다. |
| RSC-RT-08 | 모든 `aws_route`에 `timeouts.create = "5m"`를 둔다. 4절의 구현 요구사항 예외 항목이다. |
| RSC-RT-09 | Association 키는 서브넷 키와 같다. 서브넷의 `route_table` 값을 바꾸면 서브넷은 재생성되지 않고 Association만 교체된다. |
| RSC-RT-11 | VGW 경로 전파는 `propagate_vgw = true`인 Route Table마다 `aws_vpn_gateway_route_propagation` 1개를 만들며 키는 RT 키와 같다. |

### 6.8 Network ACL

| ID | 요구사항 |
| --- | --- |
| RSC-NACL-01 | 전용 NACL은 스택당 1개인 `stack_subnets.<stack>.nacl` 또는 Shared Public용 `shared_public.nacl`로 정의한다. 스택 NACL은 그 스택의 모든 서브넷을 하나의 NACL에 연결하며, 서브넷별·계층별 NACL은 두지 않는다. 정의하지 않은 서브넷은 기본 NACL(RSC-DEF-03)에 연결된다. `vpc_endpoint_subnets`는 전용 NACL 입력을 두지 않으며 항상 기본 NACL에 연결된다. 모듈은 스택마다 NACL을 두도록 강제하지 않으며 권장 룰 골격도 제공하지 않는다. 호출자 참고 예시는 README의 "Shared Service 접근 정책 예시" 절에 둔다(ARCHITECTURE 5.1절). |
| RSC-NACL-02 | NACL 객체는 `ingress`, `egress` 두 필드를 가지며 각각 룰 이름을 키로 하는 Map이다. 두 필드는 선택(기본 `{}`)이고, 한 방향이 비어 있으면 그 방향은 룰이 없어 AWS 기본 동작(전체 거부)이 된다. 룰 값은 `rule_number`, `rule_action`, `protocol`(필수), `from_port`, `to_port`, `cidr_block`, `ipv6_cidr_block`, `icmp_type`, `icmp_code`(선택)이며 모두 `aws_network_acl_rule`의 인자 이름이다. `rule_action`은 `"allow"`·`"deny"` 둘 중 하나다. `protocol` 허용 값과 포트·ICMP 규칙은 ARCHITECTURE 8.3절을 따른다. 다음이면 plan 실패: `rule_action`이 허용 값 밖일 때, `rule_number`가 `1`~`32766` 밖일 때, `cidr_block`과 `ipv6_cidr_block` 중 정확히 하나만 준 것이 아닐 때, ARCHITECTURE 8.3절 규칙을 어길 때. |
| RSC-NACL-03 | 같은 NACL·방향 안에서 `rule_number` 중복은 plan 실패. |
| RSC-NACL-05 | NACL은 IPv4 룰(`cidr_block`)과 IPv6 룰(`ipv6_cidr_block`)이 분리되어 있고 어느 룰에도 걸리지 않는 트래픽은 거부된다. `enable_ipv6 = true`이면 IPv6 CIDR을 가진 서브넷(RSC-VPC-05)에 붙는 전용 NACL은 IPv4 룰과 대응하는 `ipv6_cidr_block` 룰을 호출자가 함께 정의한다. 모듈은 IPv4 룰을 IPv6로 복제·도출하지 않으며, 대응 룰이 없으면 그 서브넷의 IPv6 트래픽이 모두 차단됨을 변수 설명에 명시한다. `enable_ipv6 = false`인데 `ipv6_cidr_block`을 가진 룰이 있으면 plan 실패. |
| RSC-NACL-06 | `ipv6_cidr_block`에 예약 값 `vpc`를 쓰면 모듈이 VPC의 IPv6 CIDR(`aws_vpc`의 `ipv6_cidr_block` 속성)로 치환한다(배경은 DEC-061). `vpc` 외의 값은 IPv6 CIDR 형식이어야 하며 위반 시 plan 실패. `vpc`는 `enable_ipv6 = true`일 때만 허용되며(RSC-NACL-05) 그 룰의 `ipv6_cidr_block`은 plan에서 미확정 값이다. `cidr_block`에는 예약 값을 두지 않는다. |

### 6.9 기본 리소스 관리 (Default SG, RT, NACL, DHCP)

VPC가 자동으로 만드는 기본 Security Group, 기본 Route Table, 기본 Network ACL은 항상 모듈이 채택해 이름과 태그를 부여한다. 채택 여부를 정하는 입력을 두지 않는다.

| ID | 요구사항 |
| --- | --- |
| RSC-DEF-01 | 기본 Security Group은 인바운드·아웃바운드 룰을 모두 비워 전면 차단한다. 룰을 추가하는 입력을 제공하지 않으며 워크로드는 전용 SG를 써야 한다. |
| RSC-DEF-02 | 기본 Route Table은 경로 없이 채택하고 어떤 서브넷도 연결하지 않는다. |
| RSC-DEF-03 | 기본 Network ACL은 채택 후에도 AWS 기본 허용 룰(IPv4·IPv6 전체 허용 ingress·egress) 그대로를 가진다. 전용 NACL이 없는 서브넷이 연결되며(AWS 기본 동작) 룰을 바꾸는 입력을 두지 않는다. 모듈은 이 NACL의 `subnet_ids`를 관리하지 않는다(`ignore_changes`). 관리하면 AWS가 자동으로 붙인 서브넷 연결을 모듈이 회수해 전용 NACL이 없는 서브넷이 어느 NACL에도 속하지 않게 된다. |
| RSC-DEF-04 | DHCP Options는 `dhcp_options` 객체가 `null`이 아닐 때만 생성·연결한다. 필드와 기본값: `domain_name`(선택, 생략 시 `context.pri_domain`. 둘 다 `null`이면 plan 실패), `domain_name_servers`(기본 `["AmazonProvidedDNS"]`), `ntp_servers`(기본 빈 목록), `netbios_name_servers`(기본 빈 목록), `netbios_node_type`(선택). |

### 6.10 VPC Endpoints

| ID | 요구사항 |
| --- | --- |
| RSC-VPCE-01 | `vpc_endpoints.gateway`는 서비스 이름 집합(`s3`, `dynamodb`)이며 Gateway Endpoint를 만들고 RSC-RT-06에 따라 RT에 연결한다. Endpoint 서비스 이름은 Interface Endpoint와 같은 `com.amazonaws.<context.region>.<service>` 형식이므로 `context.region`이 `null`이면 plan 실패(ARCHITECTURE 10절). |
| RSC-VPCE-02 | `vpc_endpoints.interface`는 서비스 이름(`ecr.api` 등)을 키로 하는 Map이며 Endpoint 서비스 이름은 `com.amazonaws.<context.region>.<service>`로 구성한다. `context.region`이 `null`이면 plan 실패(ARCHITECTURE 10절). 값은 선택 `private_dns_enabled`(기본 `true`), 선택 `policy`, 선택 `security_group_names`(`security_groups`의 키), 선택 `security_group_ids`(호출자가 만든 SG ID). 두 SG 필드는 ENI와 같은 방식이다(RSC-ENI-05). |
| RSC-VPCE-03 | Interface Endpoint는 `vpc_endpoint_subnets`(RSC-VPCE-07)의 모든 서브넷에 ENI를 만든다. `vpc_endpoints.interface`가 비어 있지 않은데 `vpc_endpoint_subnets`가 비어 있으면 plan 실패. |
| RSC-VPCE-04 | Interface Endpoint에 붙는 SG는 `security_group_names`(모듈 SG)와 `security_group_ids`(호출자 SG)의 합집합이다. 둘 다 비어 있는 Interface Endpoint가 1개 이상이면 모듈이 Endpoint 전용 SG 1개를 만들어 그 Endpoint들에만 붙이고, VPC CIDR과 보조 CIDR에서 443 인바운드만 허용하며, `enable_ipv6 = true`이면 VPC의 IPv6 CIDR(`aws_vpc`의 `ipv6_cidr_block` 속성)에서의 443 인바운드도 함께 허용한다. 모든 Interface Endpoint가 SG를 지정했거나 Interface Endpoint가 없으면 전용 SG를 만들지 않으며 `vpc_endpoint_security_group_id` 출력은 `null`이다(ARCHITECTURE 9절). |
| RSC-VPCE-07 | `vpc_endpoint_subnets`(ARCHITECTURE 2.3절 서브넷 Map, 선택, 기본 `{}`)는 Interface VPC Endpoint ENI 배치 전용 서브넷이다. 워크로드는 여기 두지 않고 `stack_subnets`의 스택으로 정의한다(ARCHITECTURE 5.1절). 각 서브넷은 기본 경로(`0.0.0.0/0`, `::/0`)가 없는 Route Table을 가리켜야 하고 같은 `az` 값을 가진 서브넷이 2개 이상이면 안 된다(Interface Endpoint는 AZ당 서브넷 1개만 받는다). 위반 시 plan 실패(검사 위치는 POLICIES 6.1절). 정의하지 않으면 관련 리소스가 0개다. |

### 6.11 VPN Gateway와 Customer Gateway

| ID | 요구사항 |
| --- | --- |
| RSC-VPN-01 | `vpn_gateway` 객체가 `null`이 아니면 VGW를 만든다. 값은 선택 `amazon_side_asn`(기본 `null`. `null`이면 AWS 기본값 `64512`가 적용된다), 선택 `availability_zone`(AZ 이름. ARCHITECTURE 2.3절의 예외), 선택 `existing_id`. 경로 전파 대상은 각 Route Table의 `propagate_vgw`가 정하며 `propagate_to` 입력은 두지 않는다. |
| RSC-VPN-02 | `vpn_gateway.existing_id`가 있으면 새로 만들지 않고 `aws_vpn_gateway_attachment`(단일 리소스, ARCHITECTURE 6절)로 이 VPC에 연결한다. Route Table의 `propagate_vgw`는 새로 만들 때와 `existing_id`를 쓸 때 모두 허용한다. `existing_id`와 함께 `amazon_side_asn` 또는 `availability_zone`을 `null`이 아닌 값으로 주면 plan 실패. |
| RSC-VPN-03 | 경로 전파 리소스는 RSC-RT-11이 정의한다. VGW 정적 경로가 필요하면 그 Route Table의 `routes`에 `gateway = "vgw"` 항목을 적는다. |
| RSC-VPN-04 | `customer_gateways`는 키 Map이며 값은 `bgp_asn`, `ip_address`(필수), 선택 `device_name`, 선택 `tags`(기본 `{}`). `type`은 `ipsec.1` 고정. |
| RSC-VPN-05 | VPN Connection 자체는 이 모듈 범위 밖이다. 출력 `vgw_id`, `cgw_ids`로 상위 모듈이 연결한다. |

### 6.12 VPC Flow Logs

`aws_flow_log`은 목적지를 하나만 갖는다. 같은 VPC를 여러 목적지에 동시에 보내려면 목적지 수만큼 Flow Log를 만들어야 하므로, 입력은 목적지 Map으로 받고 항목마다 리소스 1개를 만든다. 목적지 리소스(로그 그룹, 버킷, Delivery Stream)와 그 IAM 롤·버킷 정책·KMS 키 정책은 모듈 범위 밖이며 ARN으로만 참조한다(RSC-FLOW-08).

| ID | 요구사항 |
| --- | --- |
| RSC-FLOW-01 | `flow_log`(선택, 기본 `null`)은 `destinations` 한 필드를 가진 객체다. `destinations`는 호출자가 정한 키의 Map이며 항목마다 `aws_flow_log` 1개를 그 키로 만든다. 항목을 빼면 그 Flow Log만 사라지고 나머지는 그대로다. `flow_log`가 `null`이면 Flow Log가 0개이고, `null`이 아닌데 `destinations`가 비어 있으면 plan 실패. |
| RSC-FLOW-02 | 항목 값은 `log_destination_arn`(필수), `log_destination_type`(필수), 선택 `iam_role_arn`, 선택 `traffic_type`·`max_aggregation_interval`·`log_format`(기본값은 RSC-FLOW-04·07), 선택 `destination_options`(RSC-FLOW-05)다. `log_destination_type`은 `cloud-watch-logs`·`s3`·`kinesis-data-firehose` 중 하나이며 그 외 값이면 plan 실패. `log_destination_arn`은 이미 만들어져 있는 목적지의 ARN이다. 로그 그룹 ARN은 전송 대상 지정 관례대로 `:*` 접미를 붙이고, 버킷 ARN은 키 접두어를 붙일 수 있으며, Firehose는 Delivery Stream ARN이다. |
| RSC-FLOW-03 | `iam_role_arn`은 타입에 따라 필수 여부가 갈린다. `cloud-watch-logs`는 필수이고 `s3`는 지정할 수 없으며, 둘 중 하나라도 어기면 plan 실패. `kinesis-data-firehose`는 검사하지 않는다. 같은 계정 전송에는 롤이 필요하고 교차 계정 전송에는 지정할 수 없는데 입력에 둘을 구분할 정보가 없어 AWS가 apply에서 판정한다. 이 예외를 변수 설명에 명시한다. |
| RSC-FLOW-04 | `traffic_type`은 `ACCEPT`, `REJECT`, `ALL`(기본 `ALL`). `max_aggregation_interval`은 `60` 또는 `600`(기본 `600`). 둘 다 항목별 값이며 validation. |
| RSC-FLOW-05 | `destination_options`는 `file_format`(`parquet`·`plain-text`, 기본 `parquet`), `hive_compatible_partitions`(`bool`, 기본 `true`), `per_hour_partition`(`bool`, 기본 `true`)을 가진 객체이며 기본값은 `null`이다. `s3` 목적지에만 지정할 수 있고 다른 유형에 지정하면 plan 실패. 리소스에는 `dynamic` 블록으로 값이 있을 때만 렌더링해 다른 유형의 Flow Log에는 블록 자체가 생기지 않는다. 객체를 생략하면 블록이 없어 AWS 기본값(`plain-text`, 파티션 없음)이 적용되므로 Parquet·파티션이 필요하면 `destination_options = {}`만 적어도 세 기본값이 채워진다. |
| RSC-FLOW-06 | S3 버킷 정책은 모듈 범위 밖이며, 변수 설명에 `delivery.logs.amazonaws.com` 허용이 필요함을 명시한다. 교차 계정 버킷은 고객 관리형 KMS 키와 그 키 정책이 전제이며 이 또한 범위 밖임을 함께 적는다. |
| RSC-FLOW-07 | 레코드 필드 정의는 항목별 `log_format`으로 받아 `aws_flow_log.log_format`에 그대로 전달한다. 기본값은 AWS v2~v5의 29개 필드를 AWS가 정의한 순서로 나열한 문자열이다. 중앙 Athena 테이블의 컬럼 순서가 이 순서와 1:1로 대응하므로, 재정의는 그 테이블을 함께 바꿀 때만 한다. 이 기본값은 `null`이 아니라 실제 문자열이므로 AWS 기본 포맷(v2 14개 필드)이 아니다. |
| RSC-FLOW-08 | 목적지 리소스는 모듈이 만들지 않는다. CloudWatch 로그 그룹, S3 버킷, Firehose Delivery Stream과 그 IAM 롤·신뢰 정책·버킷 정책·KMS 키 정책은 그 리소스를 소유한 스택이 만들고 이 모듈은 ARN만 참조한다. 로그 그룹 생성 입력(`create_log_group`, `retention_in_days`, `kms_key_id`)은 두지 않는다. |

### 6.13 Private DNS (Route53 Private Hosted Zone)

| ID | 요구사항 |
| --- | --- |
| RSC-DNS-01 | `private_dns` 객체가 `null`이 아니면 Private Hosted Zone 1개를 만들고 이 VPC에 연결한다. `domain_name`을 생략하면 `context.pri_domain`을 쓰고, 둘 다 `null`이면 plan 실패. |
| RSC-DNS-02 | `private_dns.additional_vpc_ids`(`set(string)`, 기본 `[]`)로 같은 계정의 다른 VPC를 존에 연결할 수 있다. |

### 6.14 출력

출력 요구사항 RSC-OUT-01·04·06 과 출력 표는 계약이므로 [ARCHITECTURE 9절](ARCHITECTURE.md#9-출력-계약)에 둔다.

---

## 7. 완료 기준

아키텍처 수준의 완료 기준이다. 경로·리소스 수, 이름·태그 일치, 실패 조건 같은 리소스 수준 기준은 [POLICIES 9.5절](POLICIES.md#95-검증-항목)이 `terraform test` 항목으로 정의한다.

아키텍처 수준의 완료 기준이다. 경로·리소스 수, 이름·태그 일치, 실패 조건 같은 리소스 수준 기준은 POLICIES 9절이 `terraform test` 항목으로 정의한다.

- 변수 추가만으로 신규 Stack을 Multi-AZ 형태로 생성할 수 있어야 하며, 신규 Workload가 증가하더라도 Terraform 모듈 코드 변경 없이 선언형 입력만으로 수평 확장할 수 있어야 한다.
- 각 Stack은 독립적인 Subnet Set을 가지며, 서브넷마다 가리킬 Route Table을 스택별로 다르게 적을 수 있어야 한다.
- 특정 Stack 제거가 다른 Stack의 Subnet, Shared Network의 Route Table·NAT, Terraform State Address에 영향을 주지 않아야 한다.
- VPC Peering 연계는 ARCHITECTURE 5.2절의 조건을 만족해야 한다.

### 7.1 Definition of Done

릴리스 전 다음을 모두 만족해야 한다.

- [ ] REQUIREMENTS·ARCHITECTURE·POLICIES 세 문서와 구현이 일치한다
- [ ] 이름 규칙([ARCHITECTURE 7절](ARCHITECTURE.md#7-이름-규칙))이 모든 리소스에 적용되었다
- [ ] 태그 병합 순서와 보호 키([POLICIES 4절](POLICIES.md#4-태그-정책))가 적용되었다
- [ ] 보안 기본값([POLICIES 5절](POLICIES.md#5-security-by-default))이 입력으로 꺼지지 않는다
- [ ] 검사 표의 모든 행([POLICIES 6.2절](POLICIES.md#62-검사-배치))이 구현되고 실패 테스트를 통과한다
- [ ] 출력 표([ARCHITECTURE 9절](ARCHITECTURE.md#9-출력-계약))의 항목이 모두 존재한다
- [ ] `terraform fmt -check` 통과
- [ ] `terraform validate` 통과(모듈 `required_version` 하한 버전에서)
- [ ] `terraform test` 전 항목 통과
- [ ] 기준 입력 5종의 `plan` 이 의도한 리소스만 만든다
- [ ] README 의 Input Variables·Outputs 표가 갱신되었다
- [ ] Breaking Change 여부를 검토하고 버전을 정했다([POLICIES 10절](POLICIES.md#10-버전과-호환성))
- [ ] 새로 내린 결정을 [DECISIONS](DECISIONS.md)에 기록했다
