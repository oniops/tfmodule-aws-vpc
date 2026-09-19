# POLICIES — 어떤 규칙을 강제하는가

> **문서 종류:** Terraform 모듈 정책 명세
> **모듈:** `tfmodule-aws-vpc`
> **답하는 질문:** 구현자는 어떤 규칙을 지켜야 하는가. 잘못된 입력은 어디서 어떻게 막히는가. 무엇을 바꾸면 무슨 일이 생기는가.
> **함께 읽기:** [REQUIREMENTS](REQUIREMENTS.md) · [ARCHITECTURE](ARCHITECTURE.md) · [DECISIONS](DECISIONS.md)

REQUIREMENTS 가 "무엇을", ARCHITECTURE 가 "어떤 구조로"를 정한다면 이 문서는 **"어떤 규칙 아래에서"** 를 정한다. 2~5절은 코드를 쓸 때, 6~8절은 입력을 설계할 때, 9~11절은 내보낼 때 적용된다.

---

## 1. Convention over Configuration

조직 표준을 기본값으로 제공하고, 사용자가 모든 세부 설정을 직접 입력하도록 설계하지 않는다. 예외가 필요한 설정에만 명시적 Override 인터페이스를 둔다.

이 모듈에서 호출자가 **선언하지 않아도 적용되는** 것은 다음과 같다.

| 항목 | 기본 동작 | 끌 수 있는가 |
| --- | --- | --- |
| 리소스 이름 | `context.name_prefix` 접두어 + 유형 접미어 | 아니오. `vpc_name` 같은 입력을 두지 않는다 |
| 공통 태그 | `context.tags` 를 모든 리소스에 병합 | 아니오. 값 덮어쓰기만 가능하다 |
| DNS 지원·호스트 이름 | 항상 활성 | 아니오(RSC-VPC-04) |
| 인스턴스 테넌시 | `default` 고정 | 아니오(RSC-VPC-04) |
| 기본 SG | 룰 없이 채택해 전면 차단 | 아니오(RSC-DEF-01) |
| 기본 RT·NACL | 경로 없이 채택, AWS 기본 허용 룰 유지 | 아니오(RSC-DEF-02·03) |
| `map_public_ip_on_launch` | `false` 고정 | 아니오(RSC-PUB-01) |
| IGW·Egress-only IGW | 그 대상을 쓰는 경로에서 파생 | 별도 입력을 두지 않는다(RSC-PUB-05, RSC-RT-05) |
| Gateway Endpoint 의 RT 연결 | 모든 Route Table 에 자동 연결 | 아니오(RSC-RT-06) |
| Endpoint 전용 SG | SG를 지정하지 않은 Interface Endpoint 가 있으면 생성 | 지정하면 만들지 않는다(RSC-VPCE-04) |

반대로 **선언해야만 생기는** 것은 Route Table 과 경로, NAT, ENI·SG, NACL, Endpoint, VGW·CGW, Flow Log, Private DNS, DHCP 다. 비용이 크거나 보안 경계를 바꾸는 리소스를 암묵적으로 만들지 않기 위해서다(8절).

---

## 2. 코드 컨벤션

- 모든 리소스는 `for_each`와 Map 키로 작성한다. 키는 호출자가 입력에서 정한 이름으로만 구성하고 목록 순서나 인덱스에서 파생하지 않는다. 배열 인덱스(`count` + `element()`)는 쓰지 않는다.
- 복수 리소스의 기본 출력은 리소스 키를 그대로 키로 갖는 Map 으로 낸다. 특정 범위만 모은 편의 출력은 그 범위 안에서 유일한 이름을 키로 쓸 수 있다. 단일 리소스가 없을 때는 `null` 을 내고 빈 문자열을 쓰지 않는다.
- 리소스 이름은 `context.name_prefix` 를 접두어로 하고 역할을 나타내는 접미어를 붙인다. 리소스별 이름 규칙은 ARCHITECTURE 7절 표를 따르고 표에 없는 예외를 만들지 않는다.
- 태그는 `merge(<조직 공통 태그>, <사용자 커스텀 tags>, { Name })` 순서로 병합하고, 뒤 단계가 앞 단계의 같은 키를 덮어쓴다. 커스텀 `tags` 는 모듈 공통 하나와 리소스 인스턴스별 하나를 두며 리소스 유형별 태그 입력은 두지 않는다. 모듈이 만드는 태그는 `Name` 하나이며 보호 키도 `Name` 하나다. 이 모듈의 병합 대상과 각 단계에 들어가는 입력은 4절이 정의한다.
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

### 2.1 입력 변수 정의 규칙

- 입력 변수는 리소스 인자에 그대로 대응되는 구조로 정의한다. 리소스에 연결되지 않는 입력 변수를 두지 않는다.
- 입력 변수는 영문 `description` 을 가지며 선택 입력만 `default` 를 가진다.
- 여러 개를 받는 입력은 `list` 대신 이름을 키로 하는 `map(object({...}))` 로 정의한다. 선택 필드는 `optional()` 로 기본값을 타입 정의에 둔다.
- 정적 기본값은 타입 정의에 두고, 다른 입력이나 AWS 에서 파생되는 기본값은 `null` 로 받아 `description` 에 파생 규칙을 명시한다. 파생 원본이 `null` 이면 plan 단계에서 실패시킨다.
- 참조는 하위 항목이 상위 키 하나를 적는 방향으로 둔다. 상위가 하위를 나열하는 입력을 두지 않으며, 예외는 AWS 리소스 인자 자체가 목록인 경우뿐이다.

### 2.2 히어독 설명

구조가 복잡한 변수(`map(object({...}))`, 중첩 `object` 등)는 `description = <<-EOF ... EOF` 히어독 형식으로 작성한다. 첫 문단에 변수의 의미와 키·필드 역할을 설명하고, 이어서 호출 시 그대로 복사해 쓸 수 있는 사용 예시(HCL)를 반드시 함께 기술한다. 예시 값은 샘플 CIDR·이름만 쓴다.

아래는 히어독 작성 형식을 보이는 예시이며 타입의 정본이 아니다. 이 모듈이 실제로 쓰는 변수 타입은 [ARCHITECTURE 8.1·8.2절](ARCHITECTURE.md#8-입력-계약)이 정의한다.

```hcl
variable "stack_subnets" {
  type = map(object({
    tags                      = optional(map(string), {})
    db_subnet_group           = optional(map(set(string)), {})
    elasticache_subnet_group  = optional(map(set(string)), {})
    subnets = map(object({
      az          = string
      cidr        = string
      route_table = string
      ipv6_index  = optional(number)
      tags        = optional(map(string), {})
    }))
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

### 2.3 Terraform 설계 원칙

- 멱등성을 최우선한다. 리소스를 동적으로 추가하거나 제거해도 이미 구성된 다른 리소스에 변경(`~`)이나 재생성(`-/+`)이 생기지 않아야 한다.
- 리소스 키는 2절의 `for_each`·Map 키 규칙을 따른다.
- 코드는 일관된 템플릿으로 작성해 같은 종류의 리소스 그룹을 같은 형태로 추가하고 제거할 수 있어야 한다. 한 그룹에만 예외 구조를 두지 않는다.
- 복잡한 구조 변환을 `locals` 에서 수행하지 않는다. 핵심 로직이라도 입력이 리소스 인자에 그대로 대응되도록 체계적인 구조의 `variables`(object, map 타입)를 먼저 정의한다.
- 가독성을 우선한다. 사용자가 `variables.tf` 와 README 만 읽고 모듈을 직관적으로 이해하고 바로 호출할 수 있어야 한다. 삼항 연산자나 조건식을 한 줄에 겹쳐 쓰지 않는다.
- 외부 모듈이 이 모듈의 리소스에 항목을 추가할 수 있어야 하는 경우(예: 다른 모듈이 Route Table 에 경로를 넣는 경우) 인라인 블록 대신 독립 리소스로 만들어 이 모듈의 plan 에 변경이 생기지 않게 한다.

---

## 3. 이름 정책

이름 규칙 표의 정본은 [ARCHITECTURE 7절](ARCHITECTURE.md#7-이름-규칙)이다. 이 절은 그 표를 강제하는 규칙만 적는다.

- 이름 접두어는 `context.name_prefix` 하나에서만 온다. 접두어를 덮어쓰는 입력을 두지 않는다.
- 모듈은 스택·AZ를 조합해 이름을 만들어 내지 않는다. `<이름>` 자리에는 호출자가 정한 마지막 마디만 들어간다.
- 호출자가 정하는 이름 키에는 소문자·숫자·`-` 만 허용하고, 예약 키(`shared-` 로 시작하는 스택 키, Security Group 키 `vpce`)를 금지한다. 위반은 plan 실패다.
- 리소스 `name` 인자로 쓰이는 이름은 `context.name_prefix` 길이에 따라 AWS 제약(가장 짧은 것은 IAM 롤 64자)을 넘을 수 있다. 모듈은 길이를 검사하지 않고 그 사실을 변수 `description` 에 적는다.
- 리소스 키 산식이나 이름 규칙을 바꾸면 배포된 리소스가 재생성된다. 10절의 MAJOR 규칙을 따른다.

---

## 4. 태그 정책

모든 리소스의 태그는 아래 두 출처를 이 순서로 병합하고 마지막에 `Name`을 붙인다. 뒤 단계가 앞 단계의 같은 키를 덮어쓴다. 병합 순서의 일반 규칙은 2절이 정의하며, 이 절은 이 모듈의 어떤 입력이 각 단계에 들어가는지를 정한다. 다른 요구사항 문서는 이 절을 참조하고 병합 대상을 다시 정의하지 않는다.

```text
tags = merge(context.tags, <사용자 커스텀 tags>, { Name = <이름> })
```

| 순서 | 출처 | 내용 | 필수 여부 |
| --- | --- | --- | --- |
| 1 | `context.tags` | 조직 공통 태그. 모든 리소스의 기반 | 필수(`context`의 일부) |
| 2 | 사용자 커스텀 `tags` | 모듈 공통 `tags` → 스택 `tags` 또는 `shared_public.tags` → 서브넷 `tags` → Route Table·NAT·ENI·SG·CGW 인스턴스별 `tags`. 같은 단계 안에서는 이 나열 순서대로 뒤가 앞을 덮어쓴다 | 선택. 각각 기본 `{}` |

리소스별로 보면 아래처럼 자기 인스턴스의 `tags`만 더한다. 각 커스텀 `tags`가 어느 리소스에 적용되는지는 4.1절이 정의한다.

```hcl
resource "aws_nat_gateway" "this" {
  tags = merge(context.tags, var.tags, var.nat_gateways[each.key].tags, { Name = "..." })
}
```

- 모듈이 만드는 태그는 `Name` 하나이며 병합 마지막에 붙인다. `ManagedBy`, `Environment` 등 조직 공통 키는 `context.tags`로 들어오므로 모듈이 다시 만들지 않는다.
- 보호 키: `Name`은 커스텀 `tags`에 포함될 수 없다. 포함되면 plan이 실패해야 한다. 그 외의 키(예: `kubernetes.io/*`, `karpenter.sh/*`)는 호출자가 자유롭게 정의하며 모듈이 생성·검사하지 않는다.
- `context.tags`의 키는 보호 키가 아니다. 커스텀 `tags`로 덮어쓸 수 있다.
- 태그의 용도(비용 배부, 조직 식별 등)는 호출자가 정한다. 모듈은 특정 용도의 태그 키를 요구하거나 검사하지 않으며 태그 용도를 위한 별도 입력을 두지 않는다.

### 4.1 각 태그 입력이 적용되는 리소스

태그 병합 순서와 보호 키는 4절을 따르며 여기서 다시 정의하지 않는다. 이 절은 각 커스텀 `tags` 입력이 어느 리소스에 적용되는지만 정한다.

- 인스턴스별 커스텀 `tags`(4절 2단계)는 스택, Shared Public, 서브넷, Route Table, NAT, ENI, Security Group, CGW가 가진다. 스택 `tags`는 그 스택의 모든 서브넷, NACL, 네 종류의 Subnet Group에 적용되고, 서브넷 `tags`는 그 서브넷 하나에, Route Table `tags`는 그 RT에, `nat_gateways.<key>.tags`는 그 NAT와 EIP에, `eni_interfaces.<key>.tags`는 그 ENI에, `security_groups.<key>.tags`는 그 SG와 그 SG의 룰 리소스에 적용된다(RSC-SG-06). 스택 서브넷에 적용되는 순서는 스택 `tags` → 서브넷 `tags`다.
- Shared Public은 `shared_public.tags`가 그 아래 모든 서브넷과 Shared Public NACL에 적용되고, 서브넷 `tags`가 그다음이다. `vpc_endpoint_subnets`는 서브넷 `tags`만 가진다.
- 모듈 공통 `tags`는 모듈이 만드는 모든 리소스에 적용된다. Flow Log, Endpoint 전용 SG, SG 룰처럼 자기 인스턴스 `tags`가 없는 리소스는 `context.tags`와 모듈 공통 `tags`(룰은 그 SG의 `tags`도)를 받는다.

---

## 5. Security by Default

보안 설정은 선택이 아니라 기본값이다. 아래 항목은 입력으로 끌 수 없다.

| 항목 | 정책 | 근거 |
| --- | --- | --- |
| 기본 Security Group | 인바운드·아웃바운드 룰을 모두 비워 전면 차단한다. 룰 추가 입력을 제공하지 않는다 | RSC-DEF-01 |
| 기본 Route Table | 경로 없이 채택하고 어떤 서브넷도 연결하지 않는다 | RSC-DEF-02 |
| 서브넷 퍼블릭 IP | `map_public_ip_on_launch` 는 `false` 고정. 공인 IP가 필요한 LB·NAT는 자체 EIP 또는 AWS 관리 IP를 쓴다 | RSC-PUB-01 |
| 모듈이 만든 SG | AWS 기본 아웃바운드 전체 허용 룰을 생성 시점에 회수한다. 아웃바운드가 필요하면 호출자가 `egress` 를 명시한다 | RSC-SG-05 |
| Endpoint 전용 SG | VPC CIDR·보조 CIDR(IPv6 사용 시 VPC IPv6 CIDR)에서 **443 인바운드만** 허용한다 | RSC-VPCE-04 |
| ENI의 SG | `security_group_names`·`security_group_ids` 가 모두 비면 빈 집합을 넘기지 않고 AWS 기본 SG가 붙는다. 그 SG는 전면 차단이다 | RSC-ENI-05 |
| VPC Endpoint Subnet | 기본 경로(`0.0.0.0/0`, `::/0`)가 없는 Route Table만 가리킬 수 있다 | RSC-VPCE-07 |
| 크리덴셜 | 모듈에 인증 정보를 두지 않는다. 외부 리소스 식별자(대상 ARN, KMS 키 ID, IAM 롤 ARN)는 입력으로만 받고 기본값으로 박지 않는다 | `CLAUDE.md` 6절 |

Override 를 허용하지 않는 영역은 위 표와 태그 보호 키 `Name`, 그리고 이름 접두어다. 그 밖의 값은 호출자가 덮어쓸 수 있다.

**모듈 범위 밖의 보안 전제.** S3 Flow Log 의 버킷 정책(`delivery.logs.amazonaws.com` 허용), 교차 계정 전송용 고객 관리형 KMS 키 정책, 목적지 IAM 롤의 신뢰 관계는 그 리소스를 소유한 스택이 갖춘다(RSC-FLOW-06·08). 포트 수준 접근 정책은 워크로드 모듈의 책임이다.

---

## 6. 입력 검증 정책

### 6.1 검증 원칙

- 입력 조합이 유효하지 않으면 `plan` 단계에서 `validation` 또는 `precondition`으로 실패해야 한다. 조건 미달을 이유로 리소스를 조용히 0개 만들지 않는다. 이 절은 검증 원칙을 정하고, 검사 하나하나를 둘 곳(`validation`인지 `precondition`인지, `precondition`이면 어느 리소스인지)은 6.2절 표가 정의한다.
- `vpc_cidr`, `secondary_cidrs`, 모든 서브넷의 `cidr`은 IPv4 CIDR 형식이어야 한다. 형식 검사는 포함·겹침 검사보다 **먼저** 끝나야 한다. 포함·겹침 검사가 `locals`에서 CIDR을 정수로 바꾸는 동안(1.5.7에는 `cidrcontains`가 없다) 형식이 깨진 값이 섞이면 `locals` 평가가 `precondition`보다 먼저 실패해 요구사항이 정한 메시지 대신 Terraform 내부 오류가 나온다. 그래서 형식 검사만 `validation`(V-25)에 두고 포함·겹침은 `precondition`(P-02)에 둔다. 6.2.2절 마지막 불릿과 같은 원칙이다.
- 모든 서브넷의 CIDR은 VPC CIDR 또는 보조 CIDR 안에 있어야 하고 서로 겹치지 않아야 한다. 위반 시 plan 실패. 검사 대상은 서브넷 CIDR 사이의 관계이며, `secondary_cidrs` 항목이 `vpc_cidr`이나 다른 보조 CIDR과 겹치는지는 검사하지 않는다. AWS가 `aws_vpc_ipv4_cidr_block_association` 생성에서 거부하기 때문이다(RSC-ENI-03과 같은 원칙).
- 입력이 다른 입력의 키를 참조하는 경우(서브넷의 `route_table`, 경로의 `nat_gateway`·`eni`, NAT의 `public_subnet`, ENI의 `subnet`·`security_group_names`, 네 종류 Subnet Group의 멤버) 참조 대상 키가 존재하지 않으면 plan 실패.
- Route Table 입력을 참조하는 검사(RSC-PUB-04, RSC-VPCE-07, 서브넷의 `route_table` 참조)는 `aws_route_table_association`과 `aws_route`의 `precondition`에 둔다(배경은 DEC-071). 경로 객체 안에서 끝나는 대상 택일 검사는 `route_tables`의 `validation`이다(6.2.1절). 검사 대상 값이 apply 전에 확정되지 않으면 그 검사는 apply 시점으로 미뤄진다.
- 파생 기본값 원칙은 2.1절을 따른다. 이 모듈에서는 `domain_name` 생략 시 `context.pri_domain`이 그 사례이며, 파생 원본이 `null`이면 plan 실패다(RSC-DEF-04, RSC-DNS-01).

[2절 코드 컨벤션](#2-코드-컨벤션)에서 이어지는 규칙은 다음과 같다.

- 허용 값이 정해진 입력은 `validation` 블록으로 검사한다.
- 입력 조합이 유효하지 않으면 `validation` 또는 `precondition` 으로 plan 단계에서 실패시킨다. 조건 미달을 이유로 리소스를 조용히 0개 만들지 않는다.
- 한 변수 안에서 끝나는 검사는 `validation` 에, 다른 입력을 함께 봐야 하는 검사(참조 대상 존재, 입력 간 조합)는 `precondition` 에 둔다.
- `precondition` 을 어느 리소스에 둘지는 참조 방향을 보고 정하며, 참조 관계상 나중에 오는 리소스에 둔다. 이 모듈의 검사별 구현 위치는 6.1절과 6.2절이 정의한다.

### 6.2 검사 배치

6.1절의 검증 원칙을 입력별로 구체화한다. 이 절이 각 검사를 `validation`과 `precondition` 중 어디에 두는지, `precondition`이면 어느 리소스에 두는지의 유일한 정의다. 본문에 검사를 추가하거나 바꾸면 같은 변경에서 아래 두 표를 함께 갱신한다. 실패 케이스 테스트는 이 두 표를 그대로 따른다(9.6절).

분류 기준은 하나다. `variable`의 `validation`은 **자기 변수 하나만** 참조할 수 있다. 다른 변수를 참조하는 `validation`은 Terraform 1.9 이상 기능이고 이 모듈의 `required_version` 하한은 `1.5.7`이므로(9.3절), 두 개 이상의 입력을 함께 봐야 하는 검사는 예외 없이 `precondition`에 둔다. 반대로 한 변수 안에서 끝나는 검사는 그 변수의 항목 여러 개를 서로 비교하는 검사(Map 키 간 중복 등)라도 `validation`이다.

#### 6.2.1 한 변수 안에서 끝나는 검사 (`validation`)

| ID | 검사 항목 | 대상 변수 | 근거 |
| --- | --- | --- | --- |
| V-01 | 경로 대상 `gateway`가 `igw`·`eigw`·`vgw` 중 하나 | `route_tables` | RSC-RT-01 |
| V-02 | 경로 객체의 네 대상 필드 택일, `network_interface_id`의 `eni-` 형식 | `route_tables` | RSC-RT-01 |
| V-03 | `gateway = "eigw"`인데 목적지가 IPv4 | `route_tables` | RSC-RT-01 |
| V-04 | `flow_log.destinations`의 키 문자 규칙과 항목별 `log_destination_type`·`traffic_type`·`max_aggregation_interval` 허용 값 | `flow_log` | RSC-FLOW-02, RSC-FLOW-04, ARCHITECTURE 7절 |
| V-05 | `destination_options`가 `s3` 목적지에만 있고 `file_format`이 허용 값 | `flow_log` | RSC-FLOW-05 |
| V-06 | `vpc_endpoints.gateway`가 `s3`·`dynamodb` | `vpc_endpoints` | RSC-VPCE-01 |
| V-07 | `dhcp_options.netbios_node_type`이 `"1"`·`"2"`·`"4"`·`"8"` | `dhcp_options` | RSC-DEF-04 |
| V-08 | `eni_interfaces.<key>.interface_type`이 `efa`·`efa-only` 중 하나이거나 `null` | `eni_interfaces` | RSC-ENI-06 |
| V-09 | `security_groups`에 예약 키 `vpce` | `security_groups` | RSC-SG-02 |
| V-10 | SG 룰 소스 다섯 필드 택일, ARCHITECTURE 8.3절 프로토콜·포트 규칙 | `security_groups` | RSC-SG-04, ARCHITECTURE 8.3절 |
| V-11 | SG 룰의 `referenced_security_group_name`이 `security_groups`에 존재 | `security_groups` | RSC-SG-04 |
| V-12 | `existing_id`와 `amazon_side_asn`·`availability_zone` 동시 지정 | `vpn_gateway` | RSC-VPN-02 |
| V-13 | 서브넷 `az`가 AZ ID 형식(`-az<번호>`로 끝남) | `shared_public`, `vpc_endpoint_subnets`, `stack_subnets` | RSC-AZ-01 |
| V-14 | 서브넷 `ipv6_index` 범위(`0`~`255`) | `shared_public`, `vpc_endpoint_subnets`, `stack_subnets` | RSC-VPC-05 |
| V-15 | 이름 키 문자 규칙(소문자·숫자·`-`) | `route_tables`, `nat_gateways`, `eni_interfaces`, `security_groups`, `customer_gateways`, `shared_public`, `vpc_endpoint_subnets`, `stack_subnets` | ARCHITECTURE 7절 |
| V-16 | 스택 키가 `shared-`로 시작 | `stack_subnets` | ARCHITECTURE 7절 |
| V-17 | 스택 `subnets`가 비어 있음 | `stack_subnets` | RSC-SUB-10 |
| V-18 | `shared_public`을 지정했는데 `subnets`가 비어 있음 | `shared_public` | RSC-PUB-01 |
| V-19 | `vpc_endpoint_subnets`에 같은 `az` 값을 가진 서브넷이 2개 이상 | `vpc_endpoint_subnets` | RSC-VPCE-07 |
| V-20 | 네 Subnet Group의 멤버가 같은 스택의 서브넷, 멤버 수(DB는 2개 AZ 이상, 나머지 셋은 1개 이상), 같은 유형 안에서 스택 간 그룹 이름 중복 | `stack_subnets` | RSC-SUB-05·09·11·12·13 |
| V-21 | NACL 룰 `rule_action` 허용 값, `rule_number` 범위(`1`~`32766`), `cidr_block`·`ipv6_cidr_block` 택일, ARCHITECTURE 8.3절 프로토콜·포트 규칙 | `shared_public`, `stack_subnets` | RSC-NACL-02, ARCHITECTURE 8.3절 |
| V-22 | 같은 NACL·방향의 `rule_number` 중복 | `shared_public`, `stack_subnets` | RSC-NACL-03 |
| V-23 | `ipv6_cidr_block` 값이 IPv6 CIDR 형식 또는 예약 값 `vpc` | `shared_public`, `stack_subnets` | RSC-NACL-06 |
| V-24 | 보호 키 `Name` 포함 | `tags`, 그리고 `tags` 필드를 가진 모든 입력 | 4절 |
| V-25 | CIDR 값이 IPv4 CIDR 형식(`can(cidrhost(x, 0))`이고 `:`를 포함하지 않음) | `vpc_cidr`, `secondary_cidrs`, `shared_public`, `vpc_endpoint_subnets`, `stack_subnets` | 6.1절 |
| V-26 | `flow_log`가 `null`이 아닌데 `destinations`가 비어 있음 | `flow_log` | RSC-FLOW-01 |
| V-27 | `cloud-watch-logs` 목적지에 `iam_role_arn`이 없거나 `s3` 목적지에 `iam_role_arn`이 있음 | `flow_log` | RSC-FLOW-03 |

#### 6.2.2 두 개 이상의 입력을 함께 보는 검사 (`precondition`)

| ID | 검사 항목 | 두는 리소스 | 근거 |
| --- | --- | --- | --- |
| P-01 | 서브넷 이름이 VPC 전체(Shared와 모든 스택)에서 유일 | `aws_vpc` | ARCHITECTURE 7절 |
| P-02 | 서브넷 CIDR이 `vpc_cidr` 또는 `secondary_cidrs` 안에 있고 서로 겹치지 않음 | `aws_vpc` | 6.1절 |
| P-03 | 모든 서브넷의 `az`를 합쳐 서로 다른 AZ ID가 2개 이상 | `aws_vpc` | RSC-AZ-02 |
| P-04 | `ipv6_index`가 VPC 안에서 중복되지 않음 | `aws_vpc` | RSC-VPC-05 |
| P-05 | `enable_ipv6 = false`인데 `ipv6_index`가 `null`이 아닌 서브넷 | `aws_vpc` | RSC-VPC-05 |
| P-06 | `enable_ipv6 = false`인데 `ipv6_cidr_block`을 가진 NACL 룰 | `aws_network_acl_rule` | RSC-NACL-05 |
| P-07 | 서브넷의 `route_table`이 `route_tables`에 존재 | `aws_route_table_association` | 6.1절 |
| P-08 | `shared_public.subnets`가 `gateway = "igw"`인 `0.0.0.0/0` 경로를 가진 RT를 가리킴 | `aws_route_table_association` | RSC-PUB-04 |
| P-09 | `vpc_endpoint_subnets`가 기본 경로(`0.0.0.0/0`, `::/0`)가 없는 RT를 가리킴 | `aws_route_table_association` | RSC-VPCE-07 |
| P-10 | 경로의 `nat_gateway`가 `nat_gateways`에 존재 | `aws_route` | 6.1절 |
| P-11 | 경로의 `eni`가 `eni_interfaces`에 존재 | `aws_route` | 6.1절, RSC-ENI-07 |
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

- `precondition`을 둘 리소스는 참조 방향으로 정한다. Route Table 입력을 참조하는 검사를 `aws_subnet`에 두면 경로가 호출자 ENI를 가리키는 구성에서 순환 참조가 생기므로 `aws_route_table_association`과 `aws_route`에 둔다(6.1절).
- 입력만 보는 VPC 전역 검사(서브넷 이름 유일, CIDR, AZ, IPv6 인덱스)는 단일 리소스인 `aws_vpc`에 모아 한 번만 평가한다. `aws_subnet`에 두면 서브넷마다 같은 전역 검사가 반복된다.
- 검사 대상 값이 apply 전에 확정되지 않으면(호출자 ENI ID 등) 그 검사는 apply 시점으로 미뤄진다(6.1절).
- `context`의 `null`일 수 있는 필드(`region`, `pri_domain`)를 쓰는 리소스를 추가하면 그 리소스의 `precondition` 행을 같은 변경에서 더한다. 필드를 쓰는 리소스가 하나 늘었는데 행이 따라오지 않으면 그 리소스에서만 요구사항 메시지 대신 Terraform 내부 오류(문자열 보간의 `null`)가 나온다. P-20이 Gateway Endpoint를 빠뜨려 그 상태였다.
- 리소스 인자가 다른 리소스를 키로 조회하는 값(ENI·Interface Endpoint의 `security_group_names` → `aws_security_group`)은 `locals`에서 **존재하는 키만 남겨** 조회하고, 키 존재 검사는 그 리소스의 `precondition`에 둔다. 걸러내지 않으면 `locals` 평가가 `precondition`보다 먼저 실패해 요구사항이 정한 메시지 대신 Terraform 내부 오류(`Invalid index`)만 나온다.

### 6.3 변수 `description` 에 적을 내용

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
| `flow_log` | S3 대상의 버킷 정책에 `delivery.logs.amazonaws.com` 허용이 필요하고, 교차 계정 버킷은 고객 관리형 KMS 키와 그 키 정책이 전제다. 둘 다 모듈 범위 밖이다 | RSC-FLOW-06 | 아니오 |
| `flow_log` | `kinesis-data-firehose`의 `iam_role_arn`만 검사 대상이 아니다. 같은 계정 전송에는 필요하고 교차 계정 전송에는 넣지 않으며, 둘을 구분할 정보가 입력에 없어 AWS가 apply에서 거부한다 | RSC-FLOW-03 | 아니오 |
| `flow_log` | `destination_options`를 생략하면 블록이 렌더링되지 않아 AWS 기본값(`plain-text`, 파티션 없음)이 된다. Parquet·파티션이 필요하면 `destination_options = {}`만 적어도 세 기본값이 채워진다 | RSC-FLOW-05 | 아니오 |
| `flow_log` | `log_format` 기본값은 AWS v2~v5 29개 필드이며 중앙 Athena 테이블 컬럼 순서와 1:1이다. 재정의는 그 테이블을 함께 바꿀 때만 한다 | RSC-FLOW-07 | 아니오 |
| `context` | `name_prefix` 길이에 따라 리소스 `name` 인자의 AWS 제약(가장 짧은 것은 IAM 롤 64자)을 넘을 수 있다. 모듈은 길이를 검사하지 않는다 | ARCHITECTURE 7절 | 아니오 |
| `vpc_cidr` | 값을 바꾸면 VPC가 재생성된다 | 7절 | 예(`-/+`) |
| `shared_public`, `vpc_endpoint_subnets`, `stack_subnets` | 서브넷 이름·`cidr`·`az`와 스택 키를 바꾸면 서브넷이 재생성된다. `route_table`은 Association만 교체된다 | 7절, RSC-RT-09 | 예(`-/+`) |
| `route_tables`, `nat_gateways` | Route Table 키, NAT 키, NAT의 `public_subnet`을 바꾸면 재생성된다 | 7절 | 예(`-/+`) |
| `eni_interfaces` | ENI 키, `subnet`, `private_ips`를 바꾸면 재생성된다 | 7절 | 예(`-/+`) |
| `security_groups` | SG 키와 `description`을 바꾸면 SG가 재생성되고, 룰 키를 바꾸면 그 룰이 교체된다. 룰의 프로토콜·포트·소스는 갱신된다 | 7절 | 예(`-/+`) |

---

## 7. 수명주기 정책

이 절이 수명주기 원칙의 유일한 정의다. 리소스별 요구사항은 이 절을 참조하고 다시 서술하지 않는다.

- 어떤 키의 항목을 추가·제거하든 그 키의 리소스만 생성·삭제하며, 다른 키의 plan 결과는 변경(`~`)·재생성(`-/+`) 0건이어야 한다. 대상은 스택, 서브넷, Route Table과 그 경로, NAT, ENI, Security Group과 그 룰, NACL과 룰, Secondary CIDR, VPC Endpoint, CGW, VGW 전파, 네 종류의 Subnet Group, 서브넷 `tags`다. IGW와 Egress-only IGW는 경로 대상에서 파생되는 단일 리소스이므로(RSC-PUB-05, RSC-RT-05) 그 대상을 쓰는 경로를 처음 추가할 때 생성되고 마지막으로 제거할 때 삭제되는 것은 이 규칙의 예외다.
- 스택 제거 시 그 스택의 서브넷, NACL, 네 종류의 Subnet Group만 삭제된다. 가리키는 서브넷이 없어진 Route Table과 NAT는 그대로 남는다(RSC-RT-03).
- 경로의 대상을 바꾸면 그 경로 1개만 교체된다. NAT의 생성·삭제는 `nat_gateways` 항목의 추가·제거가 정하며 경로가 참조를 끊는 것만으로는 NAT가 사라지지 않는다. 마지막 `gateway = "igw"` 경로를 지우면 IGW가, 마지막 `gateway = "eigw"` 경로를 지우면 Egress-only IGW가 함께 삭제된다(첫 항목의 예외).
- 서브넷의 `route_table` 값 변경은 서브넷 재생성이 아니라 Association 교체다(RSC-RT-09).
- Security Group 룰은 키(룰 이름)나 소속 SG가 바뀌면 교체되고, `ip_protocol`·포트·소스·`description`은 그 룰 리소스 안에서 갱신된다. provider가 룰 리소스의 이 필드들을 `ModifySecurityGroupRules`로 수정하므로 룰을 다시 만들지 않아 통신 단절이 없다.
- 생성 후 변경이 곧 재생성을 뜻하는 입력(`vpc_cidr`, 서브넷 이름·`cidr`·`az`, 스택 키, Route Table 키, NAT 키, NAT의 `public_subnet`, ENI 키, ENI의 `subnet`·`private_ips`, Security Group 키, SG의 `description`)은 변수 설명에 "변경 시 재생성"을 명시하고, 필요하면 호출자가 `moved` 블록을 쓰도록 안내한다.

---

## 8. 비용 정책

비용이 큰 리소스를 암묵적으로 만들지 않고, 비용이 드는 선택을 변수 설명으로 드러낸다.

| 리소스 | 정책 |
| --- | --- |
| NAT Gateway | `nat_gateways` 에 선언한 만큼만 만든다. 입력이 비면 0개다. 여러 Route Table 이 한 NAT를 참조할 수 있어 경로를 나눠도 NAT가 늘지 않는다(RSC-NAT-08) |
| Cross-AZ 트래픽 | 서브넷 AZ와 NAT의 `public_subnet` AZ가 다르면 Cross-AZ 경로가 된다. 모듈은 허용하되 변수 설명에 비용·장애 영향을 명시한다(RSC-NAT-06) |
| EIP | NAT 항목마다 1개를 만들되 `eip_allocation_id` 로 기존 EIP를 재사용할 수 있다(RSC-NAT-03) |
| Interface Endpoint | `vpc_endpoints.interface` 에 적은 서비스만 만든다. AZ마다 ENI가 생기므로 `vpc_endpoint_subnets` 수가 곧 ENI 수다 |
| Flow Log | `flow_log` 가 `null` 이면 0개다. 목적지 하나가 Flow Log 하나이므로 목적지를 더하면 그만큼 요금이 붙는다(RSC-FLOW-01) |
| 로그 보존·스토리지 | 목적지 리소스를 모듈이 만들지 않으므로 보존 기간과 스토리지 비용은 그 리소스를 소유한 스택이 정한다(RSC-FLOW-08) |
| Public IPv4 | 서브넷 자동 할당을 끄고(RSC-PUB-01) 공인 IP는 EIP나 AWS 관리 IP로 제한한다 |

---

## 9. 검증과 테스트

### 9.1 명령

| 구분 | 명령 | 비고 |
| --- | --- | --- |
| 포맷 | `terraform fmt -check *.tf` (로컬에 `tests/` 가 있으면 `terraform fmt -check -recursive tests/` 도) | 적용 범위는 2절 마지막 항목. `examples/` 는 대상이 아니다 |
| 검증 | `terraform init -backend=false && terraform validate` | 루트에서 실행 |
| 계획 | `cd examples/<이름> && terraform init && terraform plan` | 9.2절 3단계. AWS 자격 증명 필요, 읽기 전용 |
| 테스트 | `terraform test -filter=tests/<대상>.tftest.hcl -var-file=requirements/<기준 입력>.tfvars -var-file=tests/context.tfvars` | 루트에서 실행. 9.2절 4단계 |

`terraform apply` 와 `terraform destroy` 는 루트와 `examples/` 어디서도 실행하지 않는다. 검증은 `validate` 와 `plan`, 그리고 `mock_provider` 아래의 `terraform test` 까지다. 테스트의 `command = apply` 는 mock 상태에만 쓰고(9.2절 4단계) AWS 를 호출하지 않으므로 이 금지의 대상이 아니다.

### 9.2 절차

테스트는 **모듈 루트의 `tests/*.tftest.hcl`** 에 작성해 루트에서 `terraform test` 로 실행한다. `examples/<이름>/` 은 `plan` 전용 검증 스택으로 남긴다. `tests/`·`examples/` 와 기준 입력 파일은 모두 `.gitignore` 로 제외된 로컬 검증 자산이며(README 의 주제별 정의 위치) 저장소에는 그것을 정의하는 이 절과 9절만 남는다. 테스트를 `examples/` 에 두면 `assert` 가 자식 모듈(`module "vpc"`)의 리소스에 닿지 않아 출력으로 드러나는 항목만 검증할 수 있기 때문이다. `CLAUDE.md` 필수 작업 지침 4항의 Mock 테스트와 회귀 테스트는 아래 4단계의 `run` 블록으로 대신한다.

1. 수정한 파일에 `terraform fmt` 를 적용한다. 검증용 임시 스택 `examples/` 는 대상이 아니므로 `-recursive` 를 루트 전체에 쓰지 않는다(2절 마지막 항목).
2. 루트에서 `terraform init -backend=false && terraform validate` 를 통과시킨다.
3. `examples/<이름>/` 에 `provider "aws"` 블록과 `module "<이름>" { source = "../../" ... }` 호출을 담은 임시 스택을 만들고, 검증 대상 입력(9절)을 `-var-file` 로 넣어 `terraform init && terraform plan` 을 실행한다. 스택이 이미 있으면 새로 만들지 않고 그 스택에 변경 내용을 반영한다.
4. `tests/<검증 대상>.tftest.hcl` 에 `run` 블록을 작성하고 루트에서 `terraform test` 로 실행한다. 작성 규칙은 아래와 같다.
   - 파일마다 `mock_provider "aws" {}` 를 선언한다(Terraform 1.7 이상). AWS 를 호출하지 않으므로 자격 증명이 필요 없고 리소스도 만들어지지 않는다. 자격 증명이 필요한 `data` 소스는 `override_data` 로 대체한다.
   - `mock_provider` 를 선언한 파일의 `run` 은 `command = apply` 를 쓸 수 있다. `command = plan` 에서는 리소스 ID 가 미확정이라 "경로의 `nat_gateway_id` 가 그 키의 NAT" 처럼 리소스끼리 참조하는 값을 비교할 수 없기 때문이다. 입력 검증만 보는 `run`(실패 케이스 등)은 `command = plan` 으로 둔다.
   - 기준 입력은 `-var-file` 로 넣는다. 다섯 기준 입력의 구성은 9.4절이 정의하며 관례상 `requirements/<이름>.tfvars` 로 만든다. 그 뒤에 해석된 `context` 객체를 담은 `tests/context.tfvars` 를 붙여 모듈 입력을 완성한다. 뒤에 오는 var-file 이 앞을 덮어쓰므로 순서를 바꾸지 않는다. 기준 입력에만 있는 `module "ctx"` 용 키(`team`, `cost_center`)는 경고만 남기고 무시된다.
   - `variables` 블록으로 입력을 주고 `assert` 로 리소스 수, `Name` 태그, 리소스 인자, Map 키가 의도와 같은지 검증한다. 검증 대상마다 파일을 나눈다.
   - provider 스키마에서 Optional+Computed 인 속성은 `mock_provider` 가 임의 값으로 채우므로 `null` 단언의 대상이 아니다. 그 속성이 비었음을 봐야 하면 함께 설정되는 관찰 가능한 속성으로 대신 검증하고, 대체할 속성이 없으면 그 한계를 테스트 파일 주석에 남긴다.
   - 2.3절 멱등성 검증으로, 항목을 하나 추가한 입력과 제거한 입력을 각각 `run` 으로 두고 기존 키의 리소스가 같은 키·같은 속성으로 남는지 `assert` 한다. 이전 상태와의 diff 는 5단계에서 본다.
   - 한 파일 안의 `run` 은 상태를 공유한다. `apply` 한 `run` 뒤의 `run` 은 그 결과 위에서 실행되므로 독립적으로 봐야 하는 검증은 파일을 나눈다.
   - 버그를 수정할 때는 재현하는 `run` 블록을 먼저 추가해 실패를 확인한 뒤 모듈을 고친다.
5. plan 판정 기준: 입력 변수 추가나 기본값 유지 변경은 기존 호출에서 변경(`~`)이나 재생성(`-/+`)이 0건이어야 한다. 1건이라도 있으면 원인을 설명하고 사용자 판단을 받는다. `terraform test` 에는 이전 상태와의 diff 를 `assert` 로 보는 수단이 없으므로, "기존 리소스 변경 0건" 류의 항목은 4단계가 아니라 이 3·5단계의 `plan` 결과로 판정한다(9.5절 판정 열).
6. 새 입력 변수를 추가했으면 3단계 호출 스택에 그 변수를 넣어 plan 결과에 의도한 리소스만 추가되는지 확인하고, 4단계에 그 변수를 검증하는 `run` 블록을 추가한다.

### 9.3 Terraform 버전

모듈의 `required_version` 하한은 `>= 1.5.7` 이다. 이 값은 재구현 뒤 `versions.tf` 에 적히지만 근거는 이 절이며, 6.2절의 `validation`·`precondition` 분류가 이 하한에 걸려 있으므로(다른 변수를 참조하는 `validation` 은 1.9 이상 기능) 하한을 올리거나 내리면 그 절을 함께 고친다.

`mock_provider` 가 Terraform 1.7 이상을 요구하므로 테스트에 한하여 1.7 이상 버전을 사용한다. 테스트는 모듈의 `required_version` 하한과 무관한 검증 절차이므로 하한은 올리지 않고 테스트를 실행하는 Terraform CLI 만 1.7 이상을 쓴다. 쓸 수 있는 CLI 가 `required_version` 하한과 같아 `mock_provider` 를 지원하지 않으면 9.2절 4단계를 건너뛰고 그 사실을 결과 보고에 적는다.

### 9.4 기준 입력

검증에는 다섯 가지 기준 입력을 쓴다. 이 절이 그 구성의 유일한 정의다. 파일 자체는 저장소에 두지 않는 로컬 검증 자산이며(README 의 주제별 정의 위치) 관례상 `requirements/<이름>.tfvars`로 만든다. 9.5절 표의 **기준 입력** 열은 아래 표의 이름을 가리킨다.

기준 입력은 `examples/` 검증 스택과 `terraform test` 가 함께 쓴다. 두 쓰임의 차이(`module "ctx"` 유무, `tests/context.tfvars` 결합)는 README 의 주제별 정의 위치이 정의하며, "모듈 대상 키"는 `context`, `team`, `cost_center`를 제외한 최상위 키를 뜻한다.

| 이름 | AZ | 담아야 하는 것 |
| --- | --- | --- |
| `basic` | 2 | 최소 구성의 기준값. Shared Public, 워크로드 스택 1개, AZ별 NAT 1개, `igw`·NAT·경로 없음 세 종류의 Route Table, DB·ElastiCache Subnet Group, S3 Gateway Endpoint, Private Hosted Zone, 모듈 공통 `tags`. `enable_ipv6`는 `false` |
| `full` | 2 | `basic`의 모든 항목에 더해 스택 전용 Public, 격리 서브넷, 보조 CIDR, 온프레미스 전용 계층, EIP 재사용, NAT 인스턴스 ENI 경로(`eni_interfaces`와 호출자 ENI 두 방식을 각각 실제 서브넷이 쓴다), `security_groups`와 룰, `shared_public.nacl`, 스택 NACL, Redshift·MemoryDB Subnet Group, VGW·CGW, DHCP, 목적지 1개(`s3`)의 Flow Log, Interface Endpoint와 `vpc_endpoint_subnets` |
| `basic_ipv6` | 2 | `basic` + IPv6(`enable_ipv6 = true`, 일부 서브넷의 `ipv6_index`, `::/0` 경로와 Egress-only IGW) |
| `full_ipv6` | 2 | `full` + IPv6. 위에 더해 IPv6 NACL 룰과 예약 값 `vpc`를 담는다 |
| `eks` | 3 | ARCHITECTURE 11.3절의 EKS 참조 구성. 스택 5개(`svc`, `auction`, `cms`, `toolchain`, `obsv`), 스택 NACL 1개, 스택별 DB Subnet Group, Interface Endpoint, 목적지 2개(`cloud-watch-logs` + `s3`)의 Flow Log |

- 항목 추가·제거를 보는 검증은 `basic`에서 한 항목을 더하거나 뺀 입력으로 만든다. `run` 블록의 `variables`로 그 항목만 덮어쓰는 방식을 쓴다.
- `basic`에 없는 기능은 `full`을 기준값으로 하거나 `basic`에 그 기능 입력만 더한 `variables`로 만든다.
- IPv4 기준 입력과 그 IPv6 짝은 IPv6 입력 외에 모든 값이 같아야 한다. 두 파일의 plan 차이가 IPv6 관련 리소스·속성에 한정되는 것이 TST-25·26의 전제다.
- `eks`는 3 AZ·스택 5개 구성의 회귀용이며 TST-37·TST-39만 쓴다. Flow Log 다중 목적지는 이 입력에만 있다. 다른 항목의 기준값으로 쓰지 않는다.
- 기준 입력에 항목을 더하거나 빼면 이 표와 9.5절의 해당 행을 같은 변경에서 갱신한다.

### 9.5 검증 항목

아래 표가 `terraform test` 검증 항목의 유일한 정의다. 한 행이 `run` 블록 하나 이상에 대응하며, 테스트 파일은 검증 대상별로 나눈다(9.2절 4단계). 항목을 더하거나 바꾸면 근거 요구사항과 같은 변경에서 이 표를 갱신한다.

| ID | 기준 입력 | 검증 내용 | 근거 | 판정 |
| --- | --- | --- | --- | --- |
| TST-01 | IPv4·IPv6 기준 입력 4종 | 모듈 대상 키와 `stack_subnets` 항목의 모든 필드가 모듈 변수 타입에 존재한다. Terraform은 `object` 타입에 없는 속성을 오류 없이 버리고 `assert`는 변수 타입을 직접 볼 수 없으므로, 필드마다 그 필드가 만드는 리소스 속성 1개 이상을 검증한다. 예: `memorydb_subnet_group` → `aws_memorydb_subnet_group` 수, 서브넷 `tags` → 그 서브넷 태그, `tags.Platform` → 모든 리소스 태그 | ARCHITECTURE 8.1절 | test |
| TST-02 | basic + 스택 1개 | 스택 1개 추가 시 plan 결과가 그 스택 키의 리소스 생성만 포함하고, 서브넷 키가 `<stack>/<name>` 형식이다 | 2.1, 2.5 | test + plan |
| TST-03 | basic − 스택 1개 | 스택 1개 제거 시 plan 결과가 그 스택 키의 리소스 삭제만 포함한다 | 2.5 | test + plan |
| TST-04 | basic ± 서브넷 1줄 | 스택 서브넷 1줄을 새 AZ로 추가해도 기존 리소스 변경 0건. 서브넷 1줄의 `tags`를 더하거나 빼도 다른 서브넷과 다른 스택의 plan 변경 0건 | 2.5 | test + plan |
| TST-05 | basic + RT 1개 | 어떤 서브넷도 가리키지 않는 `route_tables` 항목 1개를 더해도 plan이 실패하지 않고 그 RT와 그 경로(Gateway Endpoint 연결 포함, 첫 `igw`·`eigw` 대상이면 7절 예외대로 IGW·Egress-only IGW)만 생성되며 기존 리소스 변경 0건 | RSC-RT-03, 2.5 | test + plan |
| TST-06 | basic − 스택 1개 | 스택 1개를 제거하면서 그 스택만 가리키던 RT를 남겨도 RT·NAT 변경 0건 | RSC-RT-03, 2.5 | test + plan |
| TST-07 | basic, full | Route Table 수가 `route_tables` 항목 수와 같고 경로 수가 모든 `routes` 항목 수의 합과 같다 | RSC-RT-01, RSC-RT-02 | test |
| TST-08 | basic, full | NAT 수가 `nat_gateways` 항목 수와 같고, 각 NAT가 `public_subnet`이 가리키는 Shared Public Subnet에 있다 | RSC-NAT-01, RSC-NAT-02 | test |
| TST-09 | basic, full | 각 경로의 대상 속성이 입력과 대응한다. `gateway = "igw"` → `gateway_id`가 IGW, `eigw` → `egress_only_gateway_id`, `vgw` → `gateway_id`가 VGW, `nat_gateway = "<키>"` → 그 키의 NAT, `eni = "<키>"` → 그 키의 ENI, `network_interface_id` → 입력값 그대로. 나머지 대상 속성은 `null`이다 | RSC-RT-01, RSC-RT-02 | test |
| TST-10 | basic, full | `gateway = "igw"` 경로가 1개 이상이면 IGW 1개가 있고 없으면 0개다. `gateway = "eigw"`와 Egress-only IGW도 같다 | RSC-PUB-05, RSC-RT-05 | test |
| TST-11 | basic, full | 각 서브넷의 Association이 가리키는 Route Table이 그 서브넷 항목의 `route_table` 값과 같고, 서브넷 수가 `shared_public.subnets` + `vpc_endpoint_subnets` + 모든 스택 서브넷의 합과 같다 | RSC-RT-09, 2.6 | test |
| TST-12 | basic + `route_table` 변경 | 서브넷의 `route_table` 값만 바꾸면 그 서브넷은 재생성되지 않고 Association 1건만 교체된다 | RSC-RT-09, 2.5 | test + plan |
| TST-13 | basic | 한 NAT를 두 Route Table의 경로가 함께 참조해도 plan이 실패하지 않고 NAT는 1개다 | RSC-NAT-08 | test |
| TST-14 | basic | 기본 NACL에 IPv4·IPv6 전체 허용 ingress·egress 룰이 있다 | RSC-DEF-03 | test |
| TST-15 | basic, full | 모든 리소스의 `Name` 태그가 ARCHITECTURE 7절 표와 일치한다. 예: 서브넷 `blb-a1` → `<prefix>-blb-a1-sn`, RT `pri-a1` → `<prefix>-pri-a1-rt`, NAT 키 `a1` → `<prefix>-a1-nat` | 2.2 | test |
| TST-16 | basic | `routes`가 비어 있는 RT에 `aws_route`가 0개이고, 그 RT를 가리키는 서브넷에는 인터넷 방향 경로가 없다 | RSC-RT-01 | test |
| TST-17 | basic + 서브넷 1줄 | 데이터 계층 이름의 스택 서브넷이 `igw` 경로를 가진 RT를 가리켜도 plan이 실패하지 않는다 | ARCHITECTURE 2.2절 | test |
| TST-18 | full | `eip_allocation_id`를 준 NAT는 `aws_eip`를 만들지 않고 `nat_eip_allocation_ids`의 그 키 값이 입력값과 같다 | RSC-NAT-03 | test |
| TST-19 | full | `gateway = "igw"` 경로를 가진 RT를 가리키는 스택 서브넷에 스택 `tags`가 적용되고 `map_public_ip_on_launch = false`다 | RSC-PUB-03 | test |
| TST-20 | full | 격리 서브넷의 CIDR이 보조 CIDR 대역 안에 있고 `vpc_secondary_cidr_association_ids`에 그 CIDR 키가 있다 | RSC-VPC-02 | test |
| TST-21 | full | `network_interface_id` 대상 경로의 `network_interface_id`가 입력값과 같다 | RSC-NAT-07, RSC-RT-01 | test |
| TST-22 | full | 목적지 1개(`s3`)를 선언하면 `aws_flow_log`가 1개이고 키가 그 목적지 키다. `log_destination`·`log_destination_type`이 입력과 같고 `iam_role_arn`이 `null`이며, `destination_options`가 `parquet`·Hive 파티션·시간별 파티션이다. 모듈이 만드는 로그 그룹·IAM 롤 리소스는 없다 | RSC-FLOW-01·02·05·08 | test |
| TST-23 | full | VGW 전파 리소스 수가 `propagate_vgw = true`인 RT 수와 같고 키가 RT 키와 같다 | RSC-RT-11 | test |
| TST-24 | full | NACL 룰 리소스 수가 두 NACL의 `ingress`·`egress` 룰 수의 합과 같다 | RSC-NACL-02 | test |
| TST-25 | basic_ipv6 | VPC가 Amazon 제공 IPv6 /56을 받고, `ipv6_index`가 있는 서브넷만 IPv6 CIDR과 `assign_ipv6_address_on_creation = true`를 갖는다. `ipv6_cidr_block`은 Optional+Computed라 `null` 단언의 대상이 아니므로(9절 도입부) 값이 없는 서브넷은 `assign_ipv6_address_on_creation = false`로 확인한다. basic.tfvars 대비 plan 차이가 VPC IPv6 속성, 서브넷 IPv6 속성, Egress-only IGW, `::/0` 경로에 한정된다 | RSC-VPC-05 | test + plan |
| TST-26 | full_ipv6 | `ipv6_cidr_block`을 준 룰은 `cidr_block`이 `null`이고 `::/0` 룰은 `ipv6_cidr_block`이 입력값이다. 예약 값 `vpc` 룰은 리소스가 존재하고 `cidr_block`이 `null`이다. full.tfvars 대비 NACL 룰 수 차이가 `ipv6_cidr_block` 룰 수와 같다 | RSC-NACL-05, RSC-NACL-06 | test + plan |
| TST-27 | full | 태그가 4절 순서로 병합된다. 같은 키를 `context.tags`와 모듈 `tags`에 다른 값으로 넣으면 모듈 `tags` 값이 남고, 스택 `tags`가 그 스택의 서브넷·NACL·DB Subnet Group·ElastiCache Subnet Group에만 적용되며, 서브넷 `tags`(`kubernetes.io/*`, `karpenter.sh/*` 포함)가 그 서브넷 하나에만 적용되고 같은 스택의 다른 서브넷에는 없다 | 4절, 2.3 | test |
| TST-28 | basic, full | 모든 출력이 키 Map 또는 `null` 가능 단일 값이며 ARCHITECTURE 9절 출력 표의 항목이 모두 존재하고, `stacks.<stack>.subnet_ids`의 키가 그 스택 서브넷 이름과 일치한다 | RSC-OUT-01, RSC-OUT-04, RSC-OUT-06 | test |
| TST-29 | basic + `nat_gateways = {}` + 기본 경로를 `eni`로 교체 | `nat_gateways`를 비우고 `pri-*` RT의 기본 경로를 `eni_interfaces`의 ENI로 바꾼 입력에서 plan이 실패하지 않고 `aws_nat_gateway`와 `aws_eip`가 0개다. 같은 방식으로 `network_interface_id`(호출자 ENI)로 바꾼 입력도 확인한다 | RSC-NAT-07, RSC-RT-01, RSC-ENI-07 | test |
| TST-30 | full_ipv6 | 모듈이 만든 Endpoint 전용 SG에 VPC IPv4·보조 CIDR의 443 인바운드와 VPC IPv6 CIDR의 443 인바운드가 모두 있다 | RSC-VPCE-04 | test |
| TST-31 | full | `eni_interfaces` 항목마다 `aws_network_interface` 1개가 그 키로 만들어지고, `subnet_id`가 `subnet` 이름의 서브넷이며 `private_ips`·`source_dest_check`·`interface_type`·`description`이 입력과 같다. `security_groups` 속성이 `security_group_names`가 가리키는 SG id와 `security_group_ids` 입력값의 합집합이다. `Name` 태그가 `<prefix>-<eni_key>-eni`다 | RSC-ENI-01~06, 2.2 | test |
| TST-32 | full | `eni` 대상 경로의 `network_interface_id`가 그 키의 ENI id와 같고 나머지 대상 속성은 `null`이다. 같은 입력의 `network_interface_id` 대상 경로와 공존한다 | RSC-ENI-07, RSC-RT-01, RSC-RT-02 | test |
| TST-33 | basic + ENI 1개 | `eni_interfaces` 항목 1개를 더해도 기존 리소스 변경 0건이고 ENI 1개만 생성된다. 어떤 경로도 그 ENI를 참조하지 않아도 plan 이 실패하지 않는다 | RSC-ENI-01, 2.5 | test + plan |
| TST-34 | full | `security_groups` 항목마다 `aws_security_group` 1개가 그 키로 만들어지고 `name`과 `Name` 태그가 `<prefix>-<sg_key>-sg`, `vpc_id`가 이 VPC다. `ingress`·`egress`는 provider에서 Optional+Computed라 plan에서 미확정 값이므로 인라인 룰 수를 `assert`하지 않는다 | RSC-SG-01, RSC-SG-03, 2.2 | test |
| TST-35 | full | `aws_vpc_security_group_ingress_rule`·`egress_rule` 수가 모든 SG의 `ingress`·`egress` 룰 수 합과 같고 키가 `<sg_key>/<direction>/<rule_name>`이다. 각 룰의 `ip_protocol`·포트·소스 필드가 입력과 같고 나머지 소스 필드는 `null`이며 `security_group_id`가 그 키의 SG다 | RSC-SG-03, RSC-SG-04, 2.1 | test |
| TST-36 | basic + `security_groups` 1개(룰 없음) | 어떤 ENI도 참조하지 않고 룰도 없는 SG를 더해도 plan이 실패하지 않고 그 SG가 선언된 대로 만들어지며, 두 방향의 룰 리소스가 0개다. `security_group_ids` 출력에 그 키가 있다 | RSC-SG-01, RSC-SG-05 | test |
| TST-37 | eks | `eks.tfvars`로 plan이 성공하고 스택 5개의 서브넷·NACL·DB Subnet Group 수가 입력과 같다. 3 AZ 구성에서 서브넷 키가 `<stack>/<name>` 형식이고 AZ ID가 3종이다 | ARCHITECTURE 11.3절, RSC-AZ-02, 2.1 | test |
| TST-38 | full | 네 종류의 Subnet Group이 각각 그 키로 만들어지고 `name`과 `Name` 태그가 `<prefix>-<key>-sng`·`-ecsng`·`-rssng`·`-mdsng`이며, 같은 그룹 이름을 유형이 다르게 써도 plan이 실패하지 않는다. 각 그룹의 `subnet_ids`가 나열한 멤버와 같다 | RSC-SUB-05·09·11·12·13, 2.2 | test |
| TST-39 | eks | 목적지 2개(`cloud-watch-logs`, `s3`)를 선언하면 `aws_flow_log`가 2개이고 키가 두 목적지 키다. `s3` 항목에만 `destination_options`가 있고 `cloud-watch-logs` 항목에는 없으며, `iam_role_arn`은 `cloud-watch-logs` 항목에만 값이 있다. `log_format`이 29개 필드 기본값이고 `flow_log_ids` 출력의 키가 두 목적지 키와 같다 | RSC-FLOW-01·03·05·07, ARCHITECTURE 9절 | test |

### 9.6 실패 케이스

실패해야 하는 입력과 그 검사를 `validation`·`precondition` 중 어디에 두는지는 4.1.1·6.2.2절 두 표가 정의한다. 이 절은 두 표를 다시 나열하지 않는다.

- 테스트는 4.1.1·6.2.2절 표의 행마다 그 검사에 걸리는 잘못된 입력을 하나 만들어 plan 실패를 확인한다. `run` 블록 ID는 그 행의 ID를 그대로 쓴 `TST-F-<행 ID>` 형식이다(예: `TST-F-V-01`, `TST-F-P-03`). 근거 요구사항 ID는 한 검사에 여러 행이 대응할 수 있어 ID로 쓰지 않는다.
- 잘못된 입력은 그 검사가 걸리는 가장 작은 기준 입력(대개 basic.tfvars)에 잘못된 값 하나만 더해 만든다. 예를 들어 `enable_ipv6 = false`인 basic.tfvars에 서브넷 `ipv6_index`, `::/0` 경로, `ipv6_cidr_block` 룰 중 하나만 더한 입력은 plan 실패다(RSC-VPC-05, RSC-RT-01, RSC-NACL-05).
- 본문에 실패 조건을 추가하거나 바꾸면 같은 변경에서 6.2절 두 표를 갱신한다. 이 절에는 조건을 다시 적지 않는다.

---

## 10. 버전과 호환성

Published Module 의 Input·Output 은 Public API 다. Semantic Versioning(`MAJOR.MINOR.PATCH`)을 적용하고 `main` 에 `vX.Y.Z` 태그를 붙인다. 기존 태그는 옮기지 않는다.

| 변경 | 버전 |
| --- | --- |
| 버그 수정, 문서 수정 | PATCH |
| 하위 호환 기능 추가(새 선택 입력, 새 출력) | MINOR |
| 아래 Breaking Change | MAJOR |

Breaking Change 로 보는 것은 다음이다.

- 입력 변수 제거, 이름 변경, 의미 변경
- 출력 제거, 이름 변경, 타입 변경
- 리소스 키 산식이나 이름 규칙 변경(배포된 리소스가 재생성된다)
- 기본 동작의 중대한 변경

MAJOR 변경은 사용자에게 먼저 알리고, 이전 버전 사용자가 무엇을 고쳐야 하는지 [DECISIONS](DECISIONS.md)에 남긴다.

---

## 11. Anti-Patterns

다음 구현 패턴을 지양한다. 괄호 안은 이 모듈이 그 함정을 피한 방식이다.

| 안티패턴 | 이 모듈의 대응 |
| --- | --- |
| **Resource Wrapper** — 정책 가치 없이 provider 인자만 그대로 노출 | 이름·태그·보안 기본값·검사를 모듈이 강제한다 |
| **Variable Explosion** — 모든 provider 인자를 변수로 노출 | 입력 표에 없는 입력을 두지 않는다. 리소스 유형별 태그 입력(`vpc_tags`, `subnet_tags` …)을 두지 않고 공통 `tags` 와 인스턴스별 `tags` 둘만 둔다 |
| **Hidden Resource Creation** — 예상하기 어려운 리소스를 암묵 생성 | 비용이 드는 리소스는 선언해야 생긴다. 파생 생성은 IGW·Egress-only IGW·Endpoint 전용 SG 셋뿐이고 조건을 요구사항에 명시한다 |
| **Environment-Specific Logic** — 환경별 분기 | 환경을 구분하는 입력을 두지 않는다. 환경 차이는 호출자의 Root Configuration 이 값으로 표현한다 |
| **Role 계층 강제** — `public`·`private`·`database` 같은 고정 계층 | 스택 서브넷은 평면 Map 이고 성격은 가리키는 Route Table 이 정한다 |
| **배열 인덱스 키** — `count` + `element()` | 모든 리소스가 호출자 이름을 키로 하는 `for_each` 다 |
| **인라인 블록** — `aws_route_table` 의 `route`, `aws_security_group` 의 `ingress` | 경로와 SG 룰을 독립 리소스로 만들어 외부 모듈이 항목을 더해도 plan 이 흔들리지 않는다 |
| **locals 변환** — 입력을 `locals` 에서 가공해 리소스로 넘김 | `locals` 는 중첩 입력의 flatten 과 검사 계산에만 쓴다 |
