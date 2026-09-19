# requirements — tfmodule-aws-vpc 요구사항 문서 세트

이 폴더는 `tfmodule-aws-vpc` 모듈이 **무엇을 만족해야 하고, 어떤 구조로 만족시키며, 어떤 규칙을 강제하고, 왜 그렇게 정했는지**를 정의한다. 모듈 사용법은 저장소 루트의 [README.md](../README.md), 저장소 운영 규칙은 [CLAUDE.md](../CLAUDE.md)에 있다.

## 한 문단 요약

여러 워크로드를 한 AWS 계정의 **Platform VPC** 하나에 올리기 위한 재사용 Terraform 모듈이다. 워크로드마다 전용 Multi-AZ 서브넷 집합("스택")을 갖고, 서브넷의 성격은 그 서브넷이 가리키는 Route Table 의 기본 경로가 정한다. 호출자는 "어떤 스택이 어느 AZ에 어떤 대역을 쓰고 어디로 나가는가"만 선언하고, 이름·태그·보안 기본값·검증은 모듈이 강제한다.

## 문서 지도

| 문서 | 답하는 질문 | 언제 읽나 |
| --- | --- | --- |
| [REQUIREMENTS.md](REQUIREMENTS.md) | 왜 존재하고, 무엇을 만들며, 어디까지 책임지는가 | 모듈을 처음 볼 때. 도입 여부를 판단할 때 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 어떤 모델로 VPC를 표현하고, 무엇을 입력하고 무엇을 돌려받는가 | 모듈을 호출할 때. 입력을 설계할 때 |
| [POLICIES.md](POLICIES.md) | 어떤 규칙을 강제하고, 잘못된 입력은 어디서 막히며, 무엇을 바꾸면 무슨 일이 생기는가 | 모듈을 고칠 때. 리뷰할 때 |
| [DECISIONS.md](DECISIONS.md) | 왜 그렇게 결정했는가 | "이건 왜 이렇게 돼 있지?" 싶을 때 |

## 읽는 순서

```text
처음 쓰는 사람
  REQUIREMENTS 1~4절  (목적·책임 범위)
      ↓
  ARCHITECTURE 1~5절  (모델)
      ↓
  루트 README Usage   (실제 호출 예시)

모듈을 고치는 사람
  REQUIREMENTS 5~6절  (요구사항 정본)
      ↓
  POLICIES 2·6·7절    (코드 컨벤션·검증 배치·수명주기)
      ↓
  POLICIES 9절        (검증과 테스트)

"왜?"가 궁금한 사람
  DECISIONS.md        (결정 하나에 행 하나)
```

## ID 체계

문서와 코드, 테스트가 같은 ID로 서로를 가리킨다. ID는 한 번 부여하면 바꾸지 않고, 삭제해도 재사용하지 않는다.

| ID | 뜻 | 정의 위치 | 어디서 참조되나 |
| --- | --- | --- | --- |
| `REQ-nn` | 목표 수준 요구사항. 스캔용 요약 | [REQUIREMENTS 5절](REQUIREMENTS.md#5-목표-요구사항) | 문서 내부 |
| `RSC-<영역>-<번호>` | 리소스 수준 요구사항. **정본** | [REQUIREMENTS 6절](REQUIREMENTS.md#6-리소스별-요구사항) | `*.tf` 주석, `tests/`, DECISIONS |
| `V-nn` | 한 변수 안에서 끝나는 검사(`validation`) | [POLICIES 6.2.1](POLICIES.md#621-한-변수-안에서-끝나는-검사-validation) | `variables.tf`, 실패 테스트 |
| `P-nn` | 두 입력 이상을 함께 보는 검사(`precondition`) | [POLICIES 6.2.2](POLICIES.md#622-두-개-이상의-입력을-함께-보는-검사-precondition) | 리소스 `lifecycle`, 실패 테스트 |
| `TST-nn` | 검증 항목 | [POLICIES 9.5](POLICIES.md#95-검증-항목) | `tests/*.tftest.hcl` |
| `TST-F-<행 ID>` | 실패 케이스. `<행 ID>`는 `V-nn`·`P-nn` | [POLICIES 9.6](POLICIES.md#96-실패-케이스) | `tests/failures.tftest.hcl` |
| `DEC-nnn` | 설계 결정 기록(ADR) | [DECISIONS.md](DECISIONS.md) | 모든 문서 |

`REQ-nn` 은 "왜·무엇"을, `RSC-*` 는 "정확히 어떻게 동작하는가"를 담는 두 계층이다. 구현과 테스트가 가리키는 것은 언제나 `RSC-*` 쪽이다.

## 주제별 정의 위치

같은 주제를 두 문서가 다르게 서술하면 아래 표의 정의 문서를 따르고 다른 쪽을 고친다. 어느 문서든 새 절이 "유일한 정의"를 선언하거나 절 번호가 바뀌면 같은 변경에서 이 표를 갱신한다.

| 주제 | 정의 문서 | 절 |
| --- | --- | --- |
| 목적, 책임 범위, 목표 요구사항 | REQUIREMENTS | 1~5 |
| 리소스별 요구사항 | REQUIREMENTS | 6 |
| 아키텍처 모델(스택·서브넷·라우팅·NAT·공유 서비스) | ARCHITECTURE | 1~5 |
| 리소스 키 체계, 이름 규칙 | ARCHITECTURE | 6, 7 |
| 입력 변수 타입·필드, 타입 약칭, 프로토콜·포트 규칙 | ARCHITECTURE | 8 |
| 출력 | ARCHITECTURE | 9 |
| `context` 계약 | ARCHITECTURE | 10 |
| EKS 스택 권장 태그 | ARCHITECTURE | 11 |
| 코드 컨벤션, Terraform 설계 원칙 | POLICIES | 2 |
| 이름·태그 정책, 태그 병합 순서와 보호 키 | POLICIES | 3, 4 |
| 보안 기본값과 Override 제한 | POLICIES | 5 |
| 검증 원칙과 검사 배치(`validation`·`precondition`) | POLICIES | 6 |
| 수명주기 | POLICIES | 7 |
| 비용 | POLICIES | 8 |
| 검증·테스트 절차, 기준 입력, 검증 항목, 실패 케이스 | POLICIES | 9 |
| 버전과 호환성 | POLICIES | 10 |
| 결정 이력 | DECISIONS | — |

저장소 운영 규칙(프로젝트 개요, 기술 스택, 디렉터리, 보안·Git 정책)은 [CLAUDE.md](../CLAUDE.md)가 정의한다.

## 검증 자산은 저장소에 없다

검증에 쓰는 기준 입력(`requirements/*.tfvars`), 테스트(`tests/`), 예제 호출 스택(`examples/`)은 `.gitignore` 로 제외된 **로컬 자산**이다. 저장소에는 그것들을 정의하는 이 문서 세트와 모듈 본체만 남는다. 검증을 재현하려면 [POLICIES 9.4절](POLICIES.md#94-기준-입력)의 기준 입력 명세를 보고 로컬에서 만든 뒤 [POLICIES 9.2절](POLICIES.md#92-절차)의 절차를 따른다.
