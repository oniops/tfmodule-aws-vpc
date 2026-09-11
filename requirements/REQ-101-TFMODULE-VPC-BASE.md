# AWS VPC Terraform 모듈 기본 요구사항 정의서

<!-- 문서 계층: REQ-101(BASE, 이 문서: 공통 전제) → REQ-102(RSC: 리소스별 요구사항) → REQ-103(EKS: 스택 태그 안내). 모듈은 이 세 문서를 기준으로 새로 구현한다. 현재 저장소의 코드와 README는 참고 자료이며 요구사항의 근거가 아니다. 작성일 2026-09-10, 개정 2026-09-11. -->

## 1. 목적

다중 EKS 및 일반 워크로드를 하나의 `Platform VPC`에서 일관되게 프로비저닝하기 위한 재사용 가능한 Terraform VPC 모듈을 구현한다.

핵심 목표는 다음과 같다.

- 워크로드 스택의 수평 확장
- 워크로드별 네트워크 수직 격리
- Multi-AZ 기반 고가용성
- Shared Service의 Private Network 접근
- NAT Gateway 및 Route Table 정책의 유연한 제어
- 스택별 비용 추적 및 AWS Billing Tag 통합
- 높은 성능 대비 낮은 운영 비용
- 워크로드의 안전한 추가·변경·제거

## 2. 기본 아키텍처 원칙

VPC는 여러 워크로드 스택을 수평적으로 수용하고, 각 스택은 독립적인 Multi-AZ Private Subnet Set으로 수직 격리한다.

```text
Platform VPC
│
├─ Shared Public Network
│  ├─ Public Subnet / AZ-A
│  ├─ Public Subnet / AZ-B
│  └─ NAT Gateway / Public ALB-NLB
│
├─ Workload Stack A
│  ├─ Private Subnet / AZ-A
│  └─ Private Subnet / AZ-B
│
├─ Workload Stack B
│  └─ Multi-AZ Private Subnet Set
│
├─ Shared Toolchain Stack
│  └─ Private access → Workload management endpoints
│
├─ Shared Observability Stack
│  └─ Private Logs / Metrics / Traces
│
└─ Shared Network Services
   ├─ VPC Endpoints
   ├─ Private DNS
   └─ Flow Logs
```

특정 서비스명이나 업무 도메인에 종속되지 않아야 하며, 임의의 워크로드 스택을 선언형 입력만으로 추가·제거할 수 있어야 한다.

## 3. Subnet / AZ 요구사항

- 각 워크로드는 다른 워크로드와 공유하지 않는 전용 Private Subnet Set을 가져야 한다.
- VPC는 최소 2개, 권장 3개 AZ에 배치한다.
- 특정 AZ 장애 시 다른 AZ에서 지속 운영 가능해야 한다.
- 신규 워크로드는 기존 Subnet 변경 없이 새로운 Subnet Set으로 수평 추가해야 한다.
- 워크로드 제거 시 해당 Subnet, Route Table, NACL, 스택 NAT 등 종속 리소스만 제거되어야 한다.
- Secondary VPC CIDR 추가를 지원하여 향후 IP 확장에 대응할 수 있어야 한다.
- Public Subnet은 기본적으로 VPC 공통 Shared Network 영역으로 구성하고 모든 스택이 공용으로 사용할 수 있어야 한다.
- 특정 스택에 별도 Public Subnet이 필요한 경우 선택적으로 Dedicated Public Subnet을 구성할 수 있어야 한다.

### 3.1 Subnet Role

서브넷은 스택 안에서 Role 단위로 구획하며, Role은 라우팅·격리 정책의 단위다. Role은 아래 네 가지로 고정하며 새 Role을 추가하지 않는다. 서브넷은 Role 안에서 AZ 그룹으로 묶어 선언한다. AZ 그룹은 그 그룹의 서브넷이 공유하는 Route Table 참조를 한 번만 적고, 그룹 안에서는 호출자가 정한 서브넷 이름을 키로 CIDR을 한 줄로 적는다. 한 AZ 그룹 안에 서브넷을 여러 개 둘 수 있다. 리소스 키는 `<stack>/<role>/<name>`이며 한 서브넷은 하나의 Role만 가진다.

| Role | 용도 | 허용되는 기본 경로 | 격리 원칙 |
| --- | --- | --- | --- |
| `public` | Internet-facing LB, NAT Gateway 배치 | `igw` 고정 | Shared Network 공용이 기본. 스택 전용 Public은 선택 |
| `private` | 워크로드 노드, Pod, Internal LB | `nat` 또는 `none` | 스택 전용. 다른 스택과 공유하지 않는다 |
| `database` | RDS, ElastiCache, EC2 기반 DB 등 데이터 계층 | `none` 기본. OS 패치 등 외부 인터넷 리소스 접근이 필요하면 `nat` | 스택 전용. 관리형 DB는 `none`을 권장하고 패치는 S3·SSM Endpoint를 우선한다 |
| `intra` | 인터넷 경로가 없는 격리 계층(내부 전용 서비스) | `none` 고정 | 스택 전용. 인터넷 경로를 두지 않는다 |

- 서브넷의 기본 경로는 서브넷이 참조하는 Route Table(5절)의 `default_route`로 정한다. Role은 참조할 수 있는 `default_route`의 범위를 제한하며, 범위를 벗어난 참조는 plan 실패다.
- Role별 경로 정책은 Role 이름을 키로 정의하므로, 한 Role의 서브넷을 추가해도 다른 Role의 리소스는 변경되지 않는다. NACL은 Role 단위가 아니라 스택당 1개로 정의한다(REQ-102 3.7).
- 각 스택은 `private` Role을 1개 AZ 이상 가져야 하며, `database`, `intra`, 스택 전용 `public`은 선택이다.
- 스택의 성격(워크로드, Toolchain, Observability, EKS 등)을 구분하는 입력은 두지 않는다. 성격을 나타내는 태그와 EKS 등 외부 컨트롤러가 요구하는 태그는 호출자가 AZ 그룹 `tags`에 직접 정의한다. REQ-103은 EKS 스택에 필요한 태그 목록을 안내할 뿐 새 Role이나 새 라우팅 규칙을 정의하지 않는다.
- `database`, `intra` Role의 인바운드 제한은 스택 NACL 입력(REQ-102 3.7)과 워크로드 Security Group으로 구성한다. 모듈이 기본 룰을 강제하지 않는다.
- Shared Network의 `public_subnets`와 `shared_private_subnets`는 스택 Role이 아니다. 이 표의 Role 제약을 적용하지 않고 각각 REQ-102 RSC-PUB-04, RSC-PUB-07의 제약을 따른다.

## 4. NAT Gateway 정책 요구사항

NAT Gateway는 모듈이 모드로 도출하지 않고, 기본 경로가 `nat`인 Route Table이 배치할 Shared Public Subnet을 **명시적으로 선언**하면 그 Route Table마다 1개 만든다. NAT의 키와 이름은 Route Table의 키를 그대로 쓰며 별도 NAT 입력은 두지 않는다.

- NAT의 개수와 위치는 `nat` Route Table 선언 그대로다. `nat` Route Table이 없으면 NAT는 0개다.
- Production 권장 구성은 사용하는 AZ마다 `nat` Route Table 1개, 곧 NAT 1개다. 비용 최소 구성으로 `nat` Route Table 1개를 여러 AZ의 서브넷이 참조할 수 있으나, 이때 Cross-AZ 데이터 전송 비용과 AZ 장애 영향이 있음을 변수 설명에 명시한다.
- 각 Private Subnet은 가능한 한 같은 AZ의 Public Subnet에 NAT를 둔 Route Table에 연결하는 것을 권장한다.
- NAT는 Route Table의 비용 분류를 따른다. Route Table에 `stack`이 지정되면 NAT도 그 스택으로 귀속된다.
- Route Table의 기본 경로를 `nat`에서 다른 값으로 바꾸면 그 NAT만 삭제되고 다른 Route Table·서브넷에는 영향을 주지 않는다.

## 5. Route Table 정책 요구사항

Route Table은 호출자가 `route_tables` 입력에 **명시적으로 선언**하고, 모든 서브넷 AZ 그룹(Shared Public·Private 포함)은 Route Table 키를 참조한다. 모듈은 모드나 규칙으로 Route Table을 도출하지 않고 스스로 만드는 Route Table도 없으며, 입력 파일만 읽어도 어느 서브넷이 어느 경로를 갖는지 드러나야 한다. Public Subnet용 IGW Route Table도 호출자가 선언한다(예: `pub = { default_route = "igw" }`).

- Route Table 항목은 호출자가 정한 키를 가지며 기본 경로 `default_route`를 `igw`, `nat`, `none` 중 하나로 선언한다. `nat`이면 NAT를 배치할 Shared Public Subnet 이름을 `nat_public_subnet`으로 함께 적는다(4절).
- 서브넷 Role은 참조할 수 있는 `default_route`를 3.1절 표대로 제한한다.
- Route Table은 기본적으로 Shared Network 리소스로 비용을 분류한다. 특정 스택 전용 Route Table은 항목에 `stack`을 지정해 그 스택으로 비용을 귀속할 수 있으며, 그 Route Table은 지정한 스택의 서브넷만 참조할 수 있다.
- Gateway Endpoint, Peering, VGW 전파 경로는 기본 경로와 독립적으로 각 절의 규칙에 따라 Route Table에 추가한다.
- 특정 Stack의 추가·삭제가 다른 Stack의 Route Table 재생성을 유발해서는 안 된다.
- Terraform Resource Address는 `for_each` 기반의 안정적인 Key를 사용해야 한다.

Resource Key는 Route Table은 호출자가 정한 키(예: `pub`, `pri-a1`)를 그대로 쓰고, NAT Gateway는 자신을 선언한 Route Table의 키(예: `pri-a1`)를 쓴다. 리소스별 키 체계의 전체 정의는 REQ-102 2.1절이다.

## 6. Shared Service Private Access 요구사항

Toolchain 및 Observability와 같은 Shared Service Stack은 `stack_subnets`의 스택으로 정의하며, 전용 Private Subnet을 사용하면서 다른 워크로드와 필요한 Private 통신을 수행할 수 있어야 한다.

### Toolchain

- CI/CD, GitOps 등에서 Workload의 Private Management Endpoint에 접근할 수 있어야 한다.
- Internal Load Balancer 또는 Private DNS 기반 접근을 지원해야 한다.
- Public IP 또는 Internet Gateway를 필수로 요구해서는 안 된다.

### Observability

- 중앙 로그, 메트릭, 트레이스 수집 스택을 지원해야 한다.
- 각 Workload에서 Logs, Metrics, Traces를 Private Network로 전달할 수 있어야 한다.
- Private IP, Internal ALB/NLB, Private DNS 등을 통한 통신을 우선해야 한다.

권장 접근 정책은 다음과 같다.

| 출발지 | 목적지 | 정책 |
| --- | --- | --- |
| Toolchain | Workload Management Endpoint | Allow |
| Workload | Toolchain | Default Deny |
| Workload | Observability Endpoint | Allow |
| Observability | Workload | 필요 시 제한적 Allow |
| Workload-A | Workload-B | Default Deny |

구현 범위: 이 모듈은 스택별 서브넷 격리, 라우팅, 스택 NACL 입력(REQ-102 3.7)까지만 제공한다. Security Group과 포트 수준의 접근 제어는 워크로드 모듈의 책임이며, 이 모듈은 접근 정책을 위한 별도 입력을 두지 않는다.

## 7. 외부 네트워크 연결 요구사항 (VPC Peering, VPN Gateway)

### 7.1 VPC Peering

- 최대 2개의 동일 리전 Cross-Account VPC Peering을 지원해야 한다.
- Peering 대상은 `context.region`과 같은 리전의 VPC로 한정한다. 리전 입력을 따로 두지 않는다.
- Peering 연결은 독립적인 선언형 입력으로 추가·제거할 수 있어야 한다.
- 외부 VPC 전체가 아닌 필요한 Shared Service 또는 Observability CIDR만 선택적으로 라우팅할 수 있어야 한다.
- 외부 워크로드의 Logs, Metrics, Traces를 Private Peering 경로로 중앙 Observability Stack에 전달할 수 있어야 한다.
- 필요 시 Toolchain 관리 트래픽도 명시적 정책으로 허용할 수 있어야 한다.
- Peering 간 Transitive Routing은 요구하지 않는다.
- 하나의 Peering 추가·삭제가 다른 Peering 또는 기존 Stack에 영향을 주지 않아야 한다.

### 7.2 VPN Gateway

- 온프레미스 등 외부 네트워크와의 Site-to-Site VPN 연결을 위해 VGW 1개와 여러 Customer Gateway를 선언형 입력으로 지원해야 한다.
- VGW의 경로 전파는 호출자가 지정한 Route Table에만 적용하며, VPN Connection 자체는 모듈 범위 밖이다. 리소스 수준 요구사항은 REQ-102 3.11절이다.

## 8. Tag 요구사항

### 8.1 태그 병합 순서 (공통 규칙)

모든 리소스의 태그는 아래 순서로 병합하며, 뒤 단계가 앞 단계의 같은 키를 덮어쓴다. 이 규칙은 모듈이 만드는 모든 리소스에 동일하게 적용되는 유일한 정의이며, 다른 요구사항 문서는 이 절을 참조하고 다시 정의하지 않는다.

| 순서 | 출처 | 내용 |
| --- | --- | --- |
| 1 | `context.tags` | 조직 공통 태그. 모든 리소스의 기반 |
| 2 | 모듈 생성 태그 | `Name`, 리소스 범위 태그(`Stack`, `ResourceScope`), `ManagedBy`, Billing 기본값(`CostCenter`, `Environment`), 리소스 유형별 입력 `resource_tags.<유형>` |
| 3 | 사용자 커스텀 태그 | 모듈 공통 `tags`, `common_billing_tags`, 스택 `tags`, 서브넷 AZ 그룹 `tags`, Route Table·Peering·CGW 인스턴스별 `tags` |

- 보호 키: `Name`, `Stack`, `ResourceScope`, `ManagedBy`는 2단계 `resource_tags`와 3단계 커스텀 태그로 덮어쓸 수 없다. 두 입력 어디에든 보호 키가 포함되면 plan이 실패해야 한다. 그 외의 키(예: `kubernetes.io/*`, `karpenter.sh/*`)는 호출자가 자유롭게 정의하며 모듈이 생성·검사하지 않는다.
- `CostCenter`, `Environment`는 보호 키가 아니다. `common_billing_tags`로 덮어쓸 수 있다.

### 8.2 Billing / Cost Allocation Tag

VPC 및 관련 리소스 비용을 Stack 단위로 추적하고 AWS Billing Cost Allocation Tag와 통합할 수 있어야 한다.

모듈이 생성하는 Billing Tag는 다음과 같다.

| 키 | 값 |
| --- | --- |
| `CostCenter` | `context.cost_center`. `common_billing_tags`로 덮어쓸 수 있다 |
| `Environment` | `context.environment`. `common_billing_tags`로 덮어쓸 수 있다 |
| `ManagedBy` | `terraform` 고정. 보호 키 |

`Platform` 등 조직이 추가로 쓰는 Billing 키는 `common_billing_tags`(`map(string)`)로 입력하며 모듈은 키 이름을 정하지 않는다.

리소스 범위 태그는 다음과 같다.

| 리소스 범위 | `Stack` | `ResourceScope` |
| --- | --- | --- |
| Stack 서브넷 | `<stack-key>` | `stack` |
| Stack 전용 그 외 리소스(NACL, DB Subnet Group, `stack`이 지정된 NAT·RT) | `<stack-key>` | `stack` |
| Shared Network 리소스 | `shared-network` | `shared` |

스택이 워크로드인지 Toolchain·Observability 같은 Shared Service인지를 나타내는 태그(예: `ServiceRole`)는 모듈이 만들지 않는다. 필요하면 호출자가 스택 `tags` 또는 AZ 그룹 `tags`에 직접 정의한다.

공유 NAT Gateway, VPC Endpoint 및 Shared Public Network 비용은 `Stack = shared-network`로 분류한 후 CUR/Athena 또는 Cost Category에서 별도 배부할 수 있어야 한다.

## 9. Terraform 입력 모델

### 9.1 context (필수)

모듈은 [tfmodule-context](https://github.com/oniops/tfmodule-context) 모듈의 출력 객체 `context`를 필수 입력으로 받는다. 참조 버전은 다음과 같다.

```hcl
module "ctx" {
  source  = "git::https://github.com/oniops/tfmodule-context.git?ref=v1.3.5"
  context = var.context
}

module "vpc" {
  source  = "git::https://github.com/oniops/tfmodule-aws-vpc.git?ref=<tag>"
  context = module.ctx.context
  # ...
}
```

`context`가 제공하는 값과 모듈에서의 용도는 다음과 같다.

| 필드 | 용도 |
| --- | --- |
| `name_prefix` | 모든 리소스 이름의 접두어. 별도 `vpc_name` 입력을 두지 않는다 |
| `tags` | 모든 리소스 태그 병합의 1단계(8.1절) |
| `region` | Peering 대상 리전(7.1절). 리소스 배치 리전은 호출자의 `provider` 가 정하며 별도 `region` 입력을 두지 않는다 |
| `environment` | `Environment` Billing Tag 기본값 |
| `cost_center` | `CostCenter` Billing Tag 기본값 |
| `region_alias`, `project`, `env_alias`, `owner`, `team` | 모듈이 직접 쓰지 않는다. tfmodule-context가 `name_prefix`와 `tags`를 만들 때 이미 반영한 값이며 스키마 일치를 위해 받는다 |
| `pri_domain` | Private DNS 도메인과 DHCP 도메인 기본값 |

- `context`는 tfmodule-context `v1.3.5`의 출력 스키마와 필드가 같아야 하며, 모듈은 이 스키마를 `variable "context"`의 `object` 타입으로 고정한다.
- 이름 접두어를 `context` 외의 입력으로 덮어쓰는 기능은 제공하지 않는다. 태그는 8.1절 병합 순서에 따라 덮어쓸 수 있으나 보호 키는 예외다.
- 리소스 이름(`Name` 태그)은 `<name_prefix>-<키>-<유형 접미어>`로 만든다. `<키>`는 호출자가 입력에서 정한 리소스 키(서브넷 이름, Route Table 키, NAT 키 등)를 그대로 쓰고, 모듈이 스택·Role·AZ를 조합해 이름을 만들어 내지 않는다. 키가 없는 단일 리소스는 `<name_prefix>-<유형 접미어>`다. 유형 접미어와 NACL·Flow Log처럼 키 형식이 다른 리소스의 이름은 REQ-102 2.2절 표가 정의하며, 이 원칙과 표가 다르면 표를 따른다.

### 9.2 주요 입력

주요 입력은 다음과 같다. 입력의 상세 타입과 필드는 REQ-102 4절이 유일한 정의이며 이 표는 대응 절을 안내하는 목록이다.

| 입력 | 역할 | 참조 절 |
| --- | --- | --- |
| `context` | 이름 접두어·공통 태그 공급원(필수) | 9.1 |
| `vpc_cidr`, `secondary_cidrs` | VPC 기본 CIDR과 확장 CIDR | 3 |
| `azs` | 배치 대상 AZ ID 목록 | 3 |
| `public_subnets` | Shared Public Network 서브넷 | 3 |
| `shared_private_subnets` | Interface VPC Endpoint ENI 배치용 Shared Private 서브넷(선택) | 2, REQ-102 3.3·3.9 |
| `route_tables` | Route Table 선언(키, 기본 경로, NAT 배치 Public Subnet) | 4, 5 |
| `stack_subnets` | 워크로드·Shared Service 스택 정의. Role별 서브넷 포함 | 2, 3, 6 |
| `vpc_endpoints`, `private_dns`, `flow_log`, `dhcp_options` | Shared Network Services. 객체가 `null`이면 비활성 | 2, REQ-102 3.8·3.9·3.12·3.13 |
| `peer_vpcs` | 외부 VPC Peering 정의 | 7.1 |
| `vpn_gateway`, `customer_gateways` | VGW, CGW 정의 | 7.2 |
| `resource_tags`, `common_billing_tags`, `tags` | 태그(8.1절 2단계 유형별 태그, 3단계 커스텀 태그) | 8 |

## 10. 완료 기준

- 변수 추가만으로 신규 Stack을 Multi-AZ 형태로 생성할 수 있어야 한다.
- 각 Stack은 독립적인 Private Subnet Set과 Route Table을 가질 수 있어야 한다.
- Public Subnet은 기본적으로 VPC 공용으로 사용하되 필요 시 Stack 전용 구성을 지원해야 한다.
- NAT Gateway와 Route Table은 입력에 선언된 그대로 생성되어야 하며, 모듈이 모드나 규칙으로 개수·위치를 도출하지 않아야 한다.
- `intra` Role 서브넷은 인터넷 기본 경로를 갖지 않아야 하고, `database` Role 서브넷은 `nat` Route Table을 명시적으로 참조한 경우에만 인터넷 기본 경로를 가져야 한다.
- Role이 허용하지 않는 `default_route`의 Route Table을 서브넷이 참조하면 plan이 실패해야 한다.
- Toolchain과 Observability Shared Service는 다른 Workload에 Private Network로 접근할 수 있어야 하며, 일반 Workload 간 기본 격리를 유지해야 한다.
- 최대 2개의 Cross-Account VPC를 Private Peering 방식으로 추가할 수 있어야 한다.
- Stack별 및 Shared Network 비용을 Billing Tag로 구분할 수 있어야 한다.
- 특정 Stack 제거가 다른 Stack의 Subnet, Route Table, NAT, Peering 또는 Terraform State Address에 영향을 주지 않아야 한다.
- 향후 신규 Workload가 증가하더라도 Terraform 모듈 코드 변경 없이 선언형 입력만으로 수평 확장할 수 있어야 한다.
- 서브넷은 3.1절 표준 Role(`public`, `private`, `database`, `intra`)로만 구획되어야 한다.
- 모든 리소스의 이름 접두어와 공통 태그는 `context`에서 파생되어야 하며, `context` 없이 모듈을 호출하면 plan이 실패해야 한다.
