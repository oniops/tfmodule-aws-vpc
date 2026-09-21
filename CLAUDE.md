# tfmodule-aws-vpc

이 문서는 Claude Code가 본 저장소에서 작업할 때 반드시 따르는 규칙을 정의한다.

IMPORTANT: 이 저장소는 재사용 모듈만 담는다. 루트와 `examples/` 어디서도 `terraform apply`, `terraform destroy`를 실행하지 않으며, 검증은 `validate`와 `examples/` 임시 스택의 `plan`까지만 한다.

IMPORTANT: 모듈 구현에 관한 규칙(강제 규칙·검증과 테스트 절차는 `requirements/REQUIREMENTS.md`, 코드 컨벤션·입력 변수·출력 구조·검사 배치는 `requirements/ARCHITECTURE.md`)은 이 두 문서가 정의한다. 이 문서는 저장소 운영 규칙만 담으며 구현 규칙을 다시 적지 않는다.

## 1. 프로젝트 개요

AWS VPC와 부속 네트워크 리소스(서브넷, 라우트 테이블, NAT/IGW, ENI·Security Group, NACL, VPC Endpoint, DHCP Options, DB·ElastiCache Subnet Group, VGW/CGW, 다중 목적지 Flow Logs, Route53 private zone)를 한 번의 호출로 만드는 재사용 Terraform 모듈이다.
설계는 `requirements/`의 requirements/ 문서 세트이 정의하고 루트 `*.tf`가 그것을 구현한다. 리소스나 입력을 더하면 이 절과 3절 파일 표, README 표를 함께 갱신한다.
입력 `context`는 [tfmodule-context](https://github.com/oniops/tfmodule-context) 모듈의 출력을 그대로 받으며, 모든 리소스 이름과 공통 태그가 여기서 파생된다.

- 원격 저장소: `github.com/oniops/tfmodule-aws-vpc`
- 기본 브랜치: `main`
- 릴리스: `vX.Y.Z` 태그. 사용자는 `?ref=`로 태그를 고정해 참조한다
- 모듈에는 `provider`, `backend` 블록이 없다. 사용 예시는 `README.md`의 Usage 절이 유일하다. 검증 자산(`tests/`, `examples/`, 기준 입력 tfvars)은 `.gitignore`로 제외되며 그것을 정의하는 요구사항 문서만 저장소에 남는다(REQUIREMENTS 문서 머리말)

## 2. 기술 스택

| 구분 | 값 | 출처 |
| --- | --- | --- |
| Terraform | `>= 1.5.7` | `versions.tf`. 근거는 REQUIREMENTS 8.3절 |
| AWS provider | `>= 6.0, < 7.0` | `versions.tf`. 2026-09-19 `validate`(CLI 1.5.7)·`terraform test` 통과(6.64.0) |
| 의존 모듈 | tfmodule-context `v1.3.5` 이상 | ARCHITECTURE 11절. 하위 버전 금지 근거는 REQUIREMENTS 10절 DEC-101 |
| 테스트 | `mock_provider` 기반 `terraform test` | 로컬 `tests/`(git 제외). 절차는 REQUIREMENTS 8.2절, 항목은 REQUIREMENTS 8.5절 |
| CI 시스템 | 없음 | 회귀는 4절 명령을 수동으로 돌려 확인한다 |

버전 제약을 바꾸면 `.terraform.lock.hcl`을 지우고 `terraform init -backend=false`를 다시 실행해 lock이 새 제약과 일치하는지 확인한다.

## 3. 디렉터리 구조

| 경로 | 역할 |
| --- | --- |
| 루트 `*.tf` | 모듈 본체. `variables-context.tf`(context), `variables.tf`(입력과 `validation`), `locals.tf`(flatten과 CIDR 검사), `vpc.tf`(VPC·IGW·EIGW·기본 리소스·DHCP), `subnets.tf`(서브넷·Association·Subnet Group), `route-tables.tf`(RT·경로·VGW 전파·Gateway Endpoint 연결), `nat.tf`, `eni.tf`(SG·룰·ENI), `nacl.tf`, `vpc-endpoints.tf`, `vpn.tf`, `flow-logs.tf`, `route53.tf`, `outputs.tf` |
| `versions.tf` | `required_version`과 provider 제약. 이 파일 외에 `terraform {}` 블록을 두지 않는다. 하한의 근거는 REQUIREMENTS 8.3절 |
| `requirements/` | 요구사항 문서 세트. `REQUIREMENTS.md`(무엇을 만족해야 하고 어떤 규칙을 강제하며 어떻게 검증하고 왜 그렇게 결정했는가), `ARCHITECTURE.md`(어떤 모델로 표현하고 무엇을 주고받으며 코드는 어떻게 구성되는가). 이 디렉터리에서 저장소에 남는 것은 `*.md`뿐이며, 검증에 쓰는 `*.tfvars`는 REQUIREMENTS 8.4절이 정의하는 로컬 자산이다 |
| `tests/` | `terraform test` 케이스. 모듈 루트 리소스를 `assert`해야 하므로 루트에 둔다(REQUIREMENTS 8.2절). `mock_provider`로 AWS를 호출하지 않는다. `.gitignore`로 제외된 로컬 검증 자산이라 평소에는 없을 수 있고, 검증 항목의 정본은 REQUIREMENTS 8.5절이다 |
| `examples/<이름>/` | 검증용 임시 호출 스택. 저장소에 남기지 않으므로 평소에는 없고 검증할 때 만든다. `provider "aws"` 블록과 `source = "../../"` 모듈 호출을 두고 plan으로 확인한다. tfmodule-context가 STS를 호출하므로 자격 증명 없이 plan하려면 동등한 `context` 객체를 로컬에서 만드는 스택을 따로 둔다. `terraform test` 케이스는 여기가 아니라 모듈 루트 `tests/`에 둔다 |

빌드 산출물은 없다. `.gitignore`가 제외하는 것은 `.terraform/`, `*.tfstate`, `.terraform.lock.hcl`, `/.idea/`, `/target/`, 그리고 검증 자산인 `/examples/`, `/tests/`, `/requirements/*.tfvars`, `/requirements/*.png`다. 저장소에 남는 것은 모듈 `*.tf`, `requirements/*.md`, `README.md`, `CLAUDE.md`, `LICENSE`뿐이다.

## 4. 빌드 · 실행 · 테스트 명령

아래 표는 빠른 참조용이며 정본은 REQUIREMENTS 8.1절이다.

| 구분 | 명령 | 비고 |
| --- | --- | --- |
| 포맷 | `terraform fmt -check *.tf` (로컬에 `tests/`가 있으면 `terraform fmt -check -recursive tests/`도) | `examples/`는 대상이 아니므로 `-recursive`를 루트 전체에 쓰지 않는다 |
| 검증 | `terraform init -backend=false && terraform validate` | — |
| 계획 | `cd examples/<이름> && terraform init && terraform plan` | AWS 자격 증명 필요, 읽기 전용 |
| 테스트 | `terraform test -filter=tests/<대상>.tftest.hcl -var-file=requirements/<기준 입력>.tfvars -var-file=tests/context.tfvars` | 루트에서 실행. `mock_provider`가 Terraform CLI 1.7 이상을 요구한다(REQUIREMENTS 8.3절). 모듈 `required_version`은 올리지 않는다 |

각 명령의 적용 범위, 실행 순서, 판정 기준, Terraform 버전 요구사항은 REQUIREMENTS 8절이 정의한다.

## 5. 필수 작업 지침

<!-- 이 블록은 프로젝트 종류와 무관하게 항상 동일하게 포함된다. 내용을 임의로 수정하거나 축약하지 않는다. -->

#### 1. 언어 및 문서 규칙

- 소스 코드, 주석, 변수 정의는 영문으로 작성한다. 예외로 `requirements/*.tfvars` 요구사항 기준 입력의 주석은 한글로 쓴다.
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
- 단위 테스트 프레임워크가 없는 저장소(IaC, 문서 등)는 REQUIREMENTS 8절에 정의한 검증 절차를 대신 따른다.

#### 5. 운영 안전 원칙

- REAL(운영) 환경을 대상으로 하는 파괴적 작업을 금지한다.
- 파괴적인 git 명령은 자동 실행하지 않는다. (`git push --force`, `git reset --hard`, `git clean` 등) 사용자가 명시적으로 요청한 경우에만, 영향 범위를 설명한 뒤 실행한다.
- 커밋과 푸시는 사용자의 요청이 있을 때만 수행한다.

## 6. 보안 정책

공통 보안 원칙은 5절 3항을 따른다. 아래에는 이 저장소에서만 필요한 규칙을 적는다.

- 모듈에는 인증 정보가 없다. `examples/` 스택의 AWS 인증은 `AWS_PROFILE` 환경 변수 또는 `provider` 블록의 `profile` 인자로만 하고, 액세스 키를 파일에 쓰지 않는다. git 제외 디렉터리라도 예외가 아니다.
- `*.tfstate`와 검증 자산(`examples/`, `tests/`, `requirements/*.tfvars`)은 절대 커밋하지 않는다. `.gitignore`에 이미 제외되어 있으나 `git add -f`로 우회하지 않고, `git add -A`나 `git add .` 결과에 이들이 보이면 `.gitignore`가 깨진 것이므로 먼저 복구한다.
- 외부 리소스 식별자(대상 ARN, KMS 키 ID, IAM 롤 ARN 등)는 입력 변수로만 받고 코드에 기본값으로 박지 않는다.
- 문서와 변수 기본값의 예시 값(도메인, 이메일, CIDR)은 샘플이다. 실제 고객 도메인이나 계정 ID를 넣지 않는다.

## 7. Git 작업 규칙

파괴적 git 명령과 커밋·푸시 시점은 5절 5항을 따른다.

| 항목 | 규칙 |
| --- | --- |
| 커밋 메시지 | `<JIRA-KEY> <한글 요약>` 한 줄. 예: `OI-1283 VGW 태그 속성값 보완` |
| 브랜치 | `feature/<JIRA-KEY>`. 예: `feature/OI-1283` |
| 이력 | 머지 커밋이 없는 선형 이력을 유지한다 |
| 릴리스 | `main`에 `vX.Y.Z` 태그. 기존 태그는 옮기지 않는다. MAJOR를 올리는 기준은 ARCHITECTURE 12절을 따른다 |
| 커밋 단위 | README 표 동시 갱신과 포맷 전용 커밋 분리는 ARCHITECTURE 12절 규칙을 따른다 |
| 스테이징 제외 | 검증 자산(`examples/`, `tests/`, `requirements/*.tfvars`, `requirements/*.png`)은 스테이징하지 않는다. `.gitignore`가 이미 제외하고 있으며 `git add -f`로 우회하지 않는다. 저장소에 남기자는 요청이 있으면 `.gitignore` 수정과 REQUIREMENTS 문서 머리말 갱신을 먼저 제안한다 |
