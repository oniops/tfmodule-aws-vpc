# tfmodule-aws-vpc

이 문서는 Claude Code가 본 저장소에서 작업할 때 반드시 따르는 규칙을 정의한다.

IMPORTANT: 이 저장소는 재사용 모듈만 담는다. 루트와 `examples/` 어디서도 `terraform apply`, `terraform destroy`를 실행하지 않으며, 검증은 `validate`와 `examples/` 임시 스택의 `plan`까지만 한다.

## 1. 프로젝트 개요

AWS VPC와 부속 네트워크 리소스(서브넷, 라우트 테이블, NAT/IGW, NACL, VGW/CGW, Flow Logs, Route53 private zone)를 한 번의 호출로 만드는 재사용 Terraform 모듈이다.
목표 설계는 `requirements/` 의 REQ-101~103 이 정의하며 VPC Endpoint, VPC Peering, DHCP Options, DB Subnet Group 을 추가로 포함한다. 현재 코드는 그 이전 구현이므로 1절 리소스 목록과 3절 파일 표는 재구현 시 함께 갱신한다.
입력 `context`는 [tfmodule-context](https://github.com/oniops/tfmodule-context) 모듈의 출력을 그대로 받으며, 모든 리소스 이름과 공통 태그가 여기서 파생된다.

- 원격 저장소: `github.com/oniops/tfmodule-aws-vpc`
- 기본 브랜치: `main`
- 릴리스: `vX.Y.Z` 태그. 사용자는 `?ref=` 로 태그를 고정해 참조한다
- 모듈에는 `provider`, `backend` 블록이 없고 테스트 디렉터리도 없다. 사용 예시는 `README.md`의 Usage 절이 유일하다
- `examples/`는 VPC 를 실제로 프로비저닝하는 샘플 스택을 임시로 두고 모듈을 검증하는 작업 공간이다. `.gitignore`에 `/examples/`로 제외되어 있어 git 스테이징 대상이 아니다

## 2. 기술 스택

| 구분 | 값 | 출처 |
| --- | --- | --- |
| Terraform | `>= 1.5.7` | `versions.tf` |
| AWS provider | `>= 6.0, < 7.0` | `versions.tf`. 2026-09-10 `init`·`validate` 통과(6.64.0) |
| 의존 모듈 | tfmodule-context | `variables-context.tf`, `README.md` |
| CI 시스템 | 없음 | — |

버전 제약을 바꾸면 `.terraform.lock.hcl`을 지우고 `terraform init -backend=false`를 다시 실행해 lock 이 새 제약과 일치하는지 확인한다.

## 3. 디렉터리 구조

| 경로 | 역할 |
| --- | --- |
| `main.tf` | VPC, 서브넷, 라우트 테이블, NACL, NAT/EIP, IGW, VGW/CGW 등 네트워크 리소스.  |
| `variables.tf` | 모듈 입력 변수 전체 |
| `variables-context.tf` | `context` 입력 객체의 스키마. 필드를 바꾸면 tfmodule-context 출력과 맞춰야 한다 |
| `outputs.tf` | 모듈 출력. README의 Outputs 표와 1:1로 대응한다 |
| `route53-zone.tf` | Route53 private hosted zone |
| `vpc-flow-logs.tf` | VPC Flow Logs (S3 또는 CloudWatch Logs 대상) |
| `versions.tf` | `required_version`과 provider 제약. 이 파일 외에 `terraform {}` 블록을 두지 않는다 |
| `requirements/` | 모듈 설계 요구사항 정의서 |
| `examples/<이름>/` | 검증용 임시 호출 스택(git 제외). `provider "aws"` 블록과 `source = "../../"` 모듈 호출을 두고 plan 으로 확인한다. 하위 `tests/*.tftest.hcl` 에 `terraform test` 케이스를 둔다. 저장소에 남기지 않으므로 다른 사람이 볼 수 있다고 가정하지 않는다 |


## 4. 빌드 · 실행 · 테스트 명령

| 구분 | 명령 | 비고 |
| --- | --- | --- |
| 포맷 | `terraform fmt -check -recursive` | 2026-09-10 기준 5개 파일이 정렬 차이로 실패한다. 처리 방식은 5절 참조 |
| 검증 | `terraform init -backend=false && terraform validate` | 루트에서 실행. 2026-09-10 통과 확인 |
| 계획 | `cd examples/<이름> && terraform init && terraform plan` | 7절 3단계 참조. AWS 자격 증명 필요, 읽기 전용 |
| 테스트 | `cd examples/<이름> && terraform test` | `examples/<이름>/tests/*.tftest.hcl` 실행. 테스트에 한하여 Terraform 1.7 이상을 사용한다(현재 로컬 1.5.7). 7절 4단계 참조 |

빌드 산출물은 없다. `.terraform/`, `*.tfstate`, `.terraform.lock.hcl`, `/examples/`는 `.gitignore`로 제외되어 있다.

## 5. 코드 컨벤션

- 모든 리소스는 `for_each`와 Map 키로 작성한다. 키는 사용자가 입력에서 정한 이름으로만 구성하고 목록 순서나 인덱스에서 파생하지 않는다.
- 출력은 리소스 키를 그대로 키로 갖는 Map 으로 낸다. 단일 리소스가 없을 때는 `null` 을 내고 빈 문자열을 쓰지 않는다.
- 리소스 이름은 `context.name_prefix` 를 접두어로 하고 역할을 나타내는 접미어를 붙인다. 리소스별 이름 규칙은 `requirements/REQ-102-TFMODULE-VPC-RSC.md` 2.2절 표를 따르고, 표에 없는 예외를 만들지 않는다.
- 태그는 `context.tags` 를 기반으로 모듈 생성 태그, 사용자 커스텀 태그 순으로 병합한다. 모듈이 식별과 비용 추적에 쓰는 태그 키는 보호 키로 정하고, 사용자가 덮어쓰려 하면 plan 단계에서 실패시킨다.
- 입력 변수는 리소스 인자에 그대로 대응되는 구조로 정의한다. 리소스에 연결되지 않는 입력 변수를 두지 않는다.
- 입력 변수는 영문 `description`을 가지며 선택 입력만 `default`를 가진다. 여러 개를 받는 입력은 `list` 대신 이름을 키로 하는 `map(object({...}))` 로 정의하고, 선택 필드는 `optional()` 로 기본값을 타입 정의에 둔다. 허용 값이 정해진 입력은 `validation` 블록으로 검사한다.
- 입력 조합이 유효하지 않으면 `validation` 또는 `precondition` 으로 plan 단계에서 실패시킨다. 조건 미달을 이유로 리소스를 조용히 0개 만들지 않는다.
- 모듈 안에 `provider` 블록, `backend` 블록, 하드코딩된 리전이나 계정 ID를 두지 않는다. 리소스 배치 리전은 호출자의 `provider` 가 정하고, Peering 대상 리전처럼 리전 값이 필요하면 `context.region` 을 쓴다.
- 입력·출력을 추가하거나 바꾸면 README의 Input Variables 표와 Outputs 표를 같은 커밋에서 갱신한다. 설명은 한글로 쓴다.
- 리소스 키 산식이나 이름 규칙을 바꾸면 이미 배포된 VPC에서 재생성이 일어난다. 이런 변경은 사용자에게 먼저 알리고 MAJOR 를 올린다. 릴리스 절차는 9절을 따른다.
- `terraform fmt`는 자신이 수정한 파일에만 적용한다. 기존 정렬 차이를 정리할 때는 기능 변경과 섞지 않고 포맷 전용 커밋으로 분리한다.

## 6. 필수 작업 지침

<!-- 이 블록은 프로젝트 종류와 무관하게 항상 동일하게 포함된다. 내용을 임의로 수정하거나 축약하지 않는다. -->

#### 1. 언어 및 문서 규칙

- 소스 코드, 주석, 변수 정의는 영문으로 작성한다.
- 마크다운 문서는 한글로 작성한다.
- 마크다운 문서의 표 형식은 반드시 한 줄을 띄우고 추가한다.

#### 2. 코드 변경 원칙

- 기존 코드를 먼저 읽는다.
- 작업과 명시적으로 관련된 코드 및 파일만 리팩터링한다. 요청 없이 인접한 함수나 파일을 리팩터링하지 않는다.
- 불필요한 리팩터링을 하지 않는다.
- 사용자의 명시적인 확인 없이 새로운 라이브러리, 패키지를 추가하지 않는다.

#### 3. 보안 원칙

- 크리덴셜, 액세스 키, 토큰, 비밀번호를 소스 코드와 문서에 하드코딩하지 않는다. 환경 변수 또는 시크릿 저장소를 사용한다.
- 로그, 에러 응답, 디버그 출력에 개인정보와 내부 식별자를 노출하지 않는다.
- 커밋 전에 시크릿 패턴 스캔을 수행한다.

#### 4. 테스트 원칙

- 모듈 단위의 기능 구현을 추가하면 Mock 테스트를 작성하고 통과시킨다.
- 버그를 수정할 때는 먼저 실패하는 회귀 테스트를 작성한 다음, 수정 사항을 구현하여 통과시킨다.
- 단위 또는 통합 테스트에서 실제 네트워크 및 외부 API 호출을 금지한다.
- 단위 테스트 프레임워크가 없는 저장소(IaC, 문서 등)는 7절 테스트 정책에 정의한 검증 절차를 대신 따른다.

#### 5. 운영 안전 원칙

- REAL(운영) 환경을 대상으로 하는 파괴적 작업을 금지한다.
- 파괴적인 git 명령은 자동 실행하지 않는다. (`git push --force`, `git reset --hard`, `git clean` 등) 사용자가 명시적으로 요청한 경우에만, 영향 범위를 설명한 뒤 실행한다.
- 커밋과 푸시는 사용자의 요청이 있을 때만 수행한다.

#### 6. Terraform 설계 원칙

<!-- 6항은 이 저장소에서 사용자가 명시적으로 추가한 고유 필수 지침이다. 1~5항 공통 블록과 구분해 관리한다. -->

- 멱등성을 최우선한다. 리소스를 동적으로 추가하거나 제거해도 이미 구성된 다른 리소스에 변경(`~`)이나 재생성(`-/+`)이 생기지 않아야 한다.
- 리소스 키는 5절의 `for_each`·Map 키 규칙을 따른다. 배열 인덱스(`count` + `element()`)는 쓰지 않는다.
- 코드는 일관된 템플릿으로 작성해 같은 종류의 리소스 그룹을 같은 형태로 추가하고 제거할 수 있어야 한다. 한 그룹에만 예외 구조를 두지 않는다.
- 복잡한 구조 변환을 `locals`에서 수행하지 않는다. 핵심 로직이라도 입력이 리소스 인자에 그대로 대응되도록 체계적인 구조의 `variables`(object, map 타입)를 먼저 정의한다.
- 가독성을 우선한다. 사용자가 `variables.tf`와 README만 읽고 모듈을 직관적으로 이해하고 바로 호출할 수 있어야 한다. 삼항 연산자나 조건식을 한 줄에 겹쳐 쓰지 않는다.
- 구조가 복잡한 변수(`map(object({...}))`, 중첩 `object` 등)는 `description = <<-EOF ... EOF` 히어독 형식으로 작성한다. 첫 문단에 변수의 의미와 키·필드 역할을 설명하고, 이어서 호출 시 그대로 복사해 쓸 수 있는 사용 예시(HCL)를 반드시 함께 기술한다. 예시 값은 샘플 CIDR·이름만 쓴다.

  ```hcl
  variable "public_subnets" {
    type = map(object({
      route_table  = string
      subnets      = map(string)
      tags         = optional(map(string), {})
      ipv6_indexes = optional(map(number), {})
    }))
    default     = {}
    description = <<-EOF
  Map of public subnet configurations keyed by AWS Availability Zone ID. Each entry defines the route table, subnet name-to-CIDR mappings, and tags to apply to the public subnets.

    public_subnets = {
      "apne2-az1" = {
        route_table = "pub"
        subnets     = { pub-a1 = "10.100.0.0/24" }
        tags        = { "kubernetes.io/role/elb" = "1" }
      }
      "apne2-az3" = {
        route_table = "pub"
        subnets     = { pub-c1 = "10.100.1.0/24" }
        tags        = { "kubernetes.io/role/elb" = "1" }
      }
    }
  EOF
  }
  ```


## 7. 테스트 정책

루트 모듈에는 테스트 파일을 두지 않는다. 테스트는 `examples/<이름>/tests/*.tftest.hcl` 에 작성해 `terraform test` 로 실행하며, 검증 스택과 함께 git 에서 제외된다. 6절 4항의 Mock 테스트와 회귀 테스트는 아래 4단계의 `run` 블록으로 대신한다.

1. 수정한 파일에 `terraform fmt` 를 적용한다.
2. 루트에서 `terraform init -backend=false && terraform validate` 를 통과시킨다.
3. `examples/<이름>/` 에 `provider "aws"` 블록과 `module "vpc" { source = "../../" ... }` 호출을 담은 임시 스택을 만들고, README Usage 값을 입력으로 넣어 `terraform init && terraform plan` 을 실행한다. 스택이 이미 있으면 새로 만들지 않고 그 스택에 변경 내용을 반영한다.
4. `examples/<이름>/tests/<검증 대상>.tftest.hcl` 에 `run` 블록을 작성하고 `cd examples/<이름> && terraform test` 로 실행한다. 작성 규칙은 아래와 같다.
   - 모든 `run` 블록은 `command = plan` 으로 고정한다. `command = apply` 는 쓰지 않는다.
   - 실제 AWS 호출 없이 실행하려면 `mock_provider "aws" {}` 를 선언한다(Terraform 1.7 이상). 자격 증명이 필요한 `data` 소스는 `override_data` 로 대체한다.
   - `variables` 블록으로 입력을 주고 `assert` 로 리소스 수, `Name` 태그, 라우트 대상, Map 키가 의도와 같은지 검증한다. 검증 대상마다 파일을 나눈다. 예: `subnets.tftest.hcl`, `nat.tftest.hcl`, `tags.tftest.hcl`.
   - 6절 6항의 멱등성 검증으로, 항목을 하나 추가한 입력과 제거한 입력을 각각 `run` 으로 두고 기존 키의 리소스 속성이 그대로인지 `assert` 한다.
   - 버그를 수정할 때는 재현하는 `run` 블록을 먼저 추가해 실패를 확인한 뒤 모듈을 고친다.
5. plan 판정 기준: 입력 변수 추가나 기본값 유지 변경은 기존 호출에서 변경(`~`)이나 재생성(`-/+`)이 0건이어야 한다. 1건이라도 있으면 원인을 설명하고 사용자 판단을 받는다.
6. 새 입력 변수를 추가했으면 3단계 호출 스택에 그 변수를 넣어 plan 결과에 의도한 리소스만 추가되는지 확인하고, 4단계에 그 변수를 검증하는 `run` 블록을 추가한다.

`mock_provider` 가 Terraform 1.7 이상을 요구하므로 테스트에 한하여 1.7 이상 버전을 사용한다. 테스트가 `examples/` 안에서만 실행되므로 모듈의 `required_version`(`>= 1.5.7`)은 올리지 않고, 로컬 Terraform CLI 만 1.7 이상으로 올려 쓴다. 로컬이 1.5.7 이면 4단계를 건너뛰고 그 사실을 결과 보고에 적는다.

## 8. 보안 정책

공통 보안 원칙은 6절 3항을 따른다. 아래에는 이 저장소에서만 필요한 규칙을 적는다.

- 모듈에는 인증 정보가 없다. `examples/` 스택의 AWS 인증은 `AWS_PROFILE` 환경 변수 또는 `provider` 블록의 `profile` 인자로만 하고, 액세스 키를 파일에 쓰지 않는다. git 제외 디렉터리라도 예외가 아니다.
- `*.tfstate` 와 `examples/` 는 절대 커밋하지 않는다. `.gitignore` 에 이미 제외되어 있으나 `git add -f` 로 우회하지 않고, `git add -A` 나 `git add .` 결과에 `examples/` 가 보이면 `.gitignore` 가 깨진 것이므로 먼저 복구한다.
- Flow Logs 대상 ARN, KMS 키 ID, IAM 롤 ARN 은 입력 변수로만 받고 코드에 기본값으로 박지 않는다.
- README 예시 값(도메인, 이메일, CIDR)은 샘플이다. 실제 고객 도메인이나 계정 ID 를 README 나 변수 기본값에 넣지 않는다.

## 9. Git 작업 규칙

파괴적 git 명령과 커밋·푸시 시점은 6절 5항을 따른다.

| 항목 | 규칙 |
| --- | --- |
| 커밋 메시지 | `<JIRA-KEY> <한글 요약>` 한 줄. 예: `OI-1283 VGW 태그 속성값 보완` |
| 브랜치 | `feature/<JIRA-KEY>`. 예: `feature/OI-1283` |
| 이력 | 머지 커밋이 없는 선형 이력을 유지한다 |
| 릴리스 | `main`에 `vX.Y.Z` 태그. 기존 태그는 옮기지 않는다. MAJOR 를 올리는 기준은 5절을 따른다 |
| 커밋 단위 | README 표 동시 갱신과 포맷 전용 커밋 분리는 5절 규칙을 따른다 |
| 스테이징 제외 | `examples/` 는 검증용 임시 스택이므로 스테이징하지 않는다. 사용자가 예제를 저장소에 남기자고 명시하면 `.gitignore` 수정을 먼저 제안한다 |
