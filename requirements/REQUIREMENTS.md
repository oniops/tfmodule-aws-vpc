# REQUIREMENTS — 무엇을 만족해야 하고 어떤 규칙으로 강제하는가

> **문서 종류:** Terraform 모듈 요구사항·정책 명세
> **모듈:** `tfmodule-aws-vpc`
> **답하는 질문:** 이 모듈은 왜 존재하고, 무엇을 만들며, 어디까지 책임지는가. 구현자는 어떤 규칙을 지켜야 하고 잘못된 입력은 어디서 막히는가. 무엇을 어떻게 검증하며, 왜 그렇게 결정했는가.
> **함께 읽기:** [ARCHITECTURE](ARCHITECTURE.md) — 어떤 모델로 표현하고 무엇을 주고받으며 코드는 어떻게 구성되고 검사는 어디에 놓이는가

이 문서는 `tfmodule-aws-vpc` 모듈이 **무엇을 만족해야 하고, 어떤 규칙을 강제하며, 어떻게 검증하고, 왜 그렇게 결정했는지**를 정의한다. 모듈이 표현하는 모델과 호출자와 주고받는 계약(입력·출력·`context`), 코드 구성 방식은 [ARCHITECTURE.md](ARCHITECTURE.md)가 정의한다. 모듈 사용법은 저장소 루트의 [README.md](../README.md), 저장소 운영 규칙은 [CLAUDE.md](../CLAUDE.md)에 있다.

## 한 문단 요약

여러 워크로드를 한 AWS 계정의 **Platform VPC** 하나에 올리기 위한 재사용 Terraform 모듈이다. 워크로드마다 전용 Multi-AZ 서브넷 집합("스택")을 갖고, 서브넷의 성격은 그 서브넷이 가리키는 Route Table 의 기본 경로가 정한다. 호출자는 "어떤 스택이 어느 AZ에 어떤 대역을 쓰고 어디로 나가는가"만 선언하고, 이름·태그·보안 기본값·검증은 모듈이 강제한다.

## 목차

1. [이 모듈은 무엇이고 왜 필요한가](#1-이-모듈은-무엇이고-왜-필요한가)
2. [추구하는 가치](#2-추구하는-가치)
3. [설계 우선순위](#3-설계-우선순위)
4. [책임 범위](#4-책임-범위)
5. [목표 요구사항](#5-목표-요구사항)
6. [리소스별 요구사항](#6-리소스별-요구사항)
7. [강제 규칙](#7-강제-규칙)
8. [검증과 테스트](#8-검증과-테스트)
9. [완료 기준](#9-완료-기준)
10. [결정 기록](#10-결정-기록)

## 문서 지도

| 문서 | 답하는 질문 | 언제 읽나 |
| --- | --- | --- |
| REQUIREMENTS(이 문서) | 왜 존재하고, 무엇을 만들며, 어디까지 책임지는가. 어떤 규칙을 강제하고 어떻게 검증하며 왜 그렇게 결정했는가 | 모듈을 처음 볼 때. 도입 여부를 판단할 때. 모듈을 고치거나 리뷰할 때. "이건 왜 이렇게 돼 있지?" 싶을 때 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 어떤 모델로 VPC를 표현하고, 무엇을 입력하고 무엇을 돌려받으며, 코드는 어떻게 구성되고, 검사는 어디에 놓이는가 | 모듈을 호출할 때. 입력을 설계할 때. 리소스 코드를 작성할 때 |

## 읽는 순서

```text
처음 쓰는 사람
  REQUIREMENTS 1~4절  (목적·책임 범위)
      ↓
  ARCHITECTURE 1~5절  (모델)
      ↓
  루트 README Usage   (실제 호출 예시)

모듈을 고치는 사람
  REQUIREMENTS 6절    (요구사항 정본)
      ↓
  REQUIREMENTS 7절    (강제 규칙: 이름·태그·보안 기본값·수명주기·비용)
      ↓
  ARCHITECTURE 9절    (검사 배치)
      ↓
  REQUIREMENTS 8절    (검증과 테스트)

"왜?"가 궁금한 사람
  REQUIREMENTS 10절   (결정 기록. 결정 하나에 행 하나)
```

## ID 체계

문서와 코드, 테스트가 같은 ID로 서로를 가리킨다. ID는 한 번 부여하면 바꾸지 않고, 삭제해도 재사용하지 않는다.

| ID | 뜻 | 정의 위치 | 어디서 참조되나 |
| --- | --- | --- | --- |
| `REQ-nn` | 목표 수준 요구사항. 스캔용 요약 | [5절](#5-목표-요구사항) | 문서 내부 |
| `RSC-<영역>-<번호>` | 리소스 수준 요구사항. **정본** | [6절](#6-리소스별-요구사항) | `*.tf` 주석, `tests/`, 10절 |
| `V-nn` | 한 변수 안에서 끝나는 검사(`validation`) | [ARCHITECTURE 9.2.1](ARCHITECTURE.md#921-한-변수-안에서-끝나는-검사-validation) | `variables.tf`, 실패 테스트 |
| `P-nn` | 두 입력 이상을 함께 보는 검사(`precondition`) | [ARCHITECTURE 9.2.2](ARCHITECTURE.md#922-두-개-이상의-입력을-함께-보는-검사-precondition) | 리소스 `lifecycle`, 실패 테스트 |
| `TST-nn` | 검증 항목 | [8.5절](#85-검증-항목) | `tests/*.tftest.hcl` |
| `TST-F-<행 ID>` | 실패 케이스. `<행 ID>`는 `V-nn`·`P-nn` | [8.6절](#86-실패-케이스) | `tests/failures.tftest.hcl` |
| `DEC-nnn` | 설계 결정 기록(ADR) | [10절](#10-결정-기록) | 모든 문서 |

`REQ-nn` 은 "왜·무엇"을, `RSC-*` 는 "정확히 어떻게 동작하는가"를 담는 두 계층이다. 구현과 테스트가 가리키는 것은 언제나 `RSC-*` 쪽이다.

## 주제별 정의 위치

같은 주제를 두 문서가 다르게 서술하면 아래 표의 정의 문서를 따르고 다른 쪽을 고친다. 어느 문서든 새 절이 "유일한 정의"를 선언하거나 절 번호가 바뀌면 같은 변경에서 이 표를 갱신한다.

| 주제 | 정의 문서 | 절 |
| --- | --- | --- |
| 목적, 책임 범위, 목표 요구사항 | REQUIREMENTS | 1~5 |
| 리소스별 요구사항 | REQUIREMENTS | 6 |
| 강제 규칙(CoC·이름·태그·보안 기본값·수명주기·비용·버전·Anti-Patterns) | REQUIREMENTS | 7 |
| 검증·테스트 절차, 기준 입력, 검증 항목, 실패 케이스 | REQUIREMENTS | 8 |
| 완료 기준 | REQUIREMENTS | 9 |
| 결정 이력 | REQUIREMENTS | 10 |
| 아키텍처 모델(스택·서브넷·라우팅·NAT·공유 서비스) | ARCHITECTURE | 1~5 |
| 리소스 키 체계, 이름 규칙 | ARCHITECTURE | 6, 7 |
| 입력 변수 타입·필드, 타입 약칭, 프로토콜·포트 규칙 | ARCHITECTURE | 8 |
| 검증 원칙과 검사 배치(`validation`·`precondition`) | ARCHITECTURE | 9 |
| 출력 | ARCHITECTURE | 10 |
| `context` 계약 | ARCHITECTURE | 11 |
| 코드 컨벤션, Terraform 설계 원칙 | ARCHITECTURE | 12 |
| EKS 스택 권장 태그 | ARCHITECTURE | 13 |

저장소 운영 규칙(프로젝트 개요, 기술 스택, 디렉터리, 보안·Git 정책)은 [CLAUDE.md](../CLAUDE.md)가 정의한다.

## 검증 자산은 저장소에 없다

검증에 쓰는 기준 입력(`requirements/*.tfvars`), 테스트(`tests/`), 예제 호출 스택(`examples/`)은 `.gitignore` 로 제외된 **로컬 자산**이다. 저장소에는 그것들을 정의하는 이 문서 세트와 모듈 본체만 남는다. 검증을 재현하려면 [8.4절](#84-기준-입력)의 기준 입력 명세를 보고 로컬에서 만든 뒤 [8.2절](#82-절차)의 절차를 따른다.

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
| **Operational Simplicity** | 스택 추가·제거·경로 변경이 그 리소스에만 영향을 준다. 수명주기는 [7.5절](#75-수명주기-정책)이 보장한다 |
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
| 8 | 비용 효율성 | NAT·Interface Endpoint 처럼 비싼 리소스를 암묵적으로 만들지 않는다([7.6절](#76-비용-정책)) |

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
| REQ-04 | 한 스택을 추가·제거해도 다른 스택과 공유 네트워크 리소스에 변경·재생성이 생기지 않는다 | MUST | [7.5절](#75-수명주기-정책) |
| REQ-05 | 모든 리소스 주소는 호출자가 정한 이름을 키로 하는 `for_each` 로 만든다 | MUST | [ARCHITECTURE 6절](ARCHITECTURE.md#6-리소스-키-체계) |
| REQ-06 | Route Table 과 경로는 호출자가 명시 선언하고 모듈이 도출하지 않는다 | MUST | RSC-RT-01~11 |
| REQ-07 | 경로 대상은 모듈 소유는 키로, 호출자 소유는 ID로 가리킨다 | MUST | RSC-RT-01, RSC-ENI-07 |
| REQ-08 | 외부 모듈이 이 모듈의 Route Table·Security Group 에 항목을 더해도 plan 이 흔들리지 않는다 | MUST | RSC-RT-02, RSC-SG-03 |
| REQ-09 | 모든 리소스 이름과 공통 태그는 `context` 에서 파생한다 | MUST | [ARCHITECTURE 7·11절](ARCHITECTURE.md#7-이름-규칙), [7.2·7.3절](#72-이름-정책) |
| REQ-10 | 잘못된 입력 조합은 apply 가 아니라 plan 에서 실패한다 | MUST | [ARCHITECTURE 9절](ARCHITECTURE.md#9-입력-검증과-검사-배치) |
| REQ-11 | 조건 미달을 이유로 리소스를 조용히 0개 만들지 않는다 | MUST | [ARCHITECTURE 9.1](ARCHITECTURE.md#91-검증-원칙) |
| REQ-12 | 기본 SG·RT·NACL을 채택해 전면 차단·무경로 상태로 둔다 | MUST | RSC-DEF-01~03 |
| REQ-13 | 위험한 기본값을 두지 않는다(`map_public_ip_on_launch`는 `false` 고정) | MUST | RSC-PUB-01 |
| REQ-14 | 비용이 큰 선택 리소스를 암묵적으로 만들지 않는다 | MUST | [7.6절](#76-비용-정책) |
| REQ-15 | 출력은 다른 모듈과의 계약이며 삭제·개명은 MAJOR 로 취급한다 | MUST | RSC-OUT-06, [7.7절](#77-버전과-호환성) |
| REQ-16 | 보조 CIDR 추가로 IP 확장에 대응할 수 있다 | MUST | RSC-VPC-02, RSC-VPC-03 |
| REQ-17 | Shared Service 스택이 Public IP 없이 워크로드와 통신할 수 있다 | MUST | [ARCHITECTURE 5.1절](ARCHITECTURE.md#51-shared-service-private-access) |
| REQ-18 | Site-to-Site VPN 을 위한 VGW 1개와 여러 CGW 를 선언형으로 지원한다 | MUST | RSC-VPN-01~05 |
| REQ-19 | `mock_provider` 기반 `terraform test` 로 자격 증명 없이 검증할 수 있다 | MUST | [8절](#8-검증과-테스트) |
| REQ-20 | IPv6 를 선택적으로 지원하고, 끄면 관련 리소스가 0개다 | SHOULD | RSC-VPC-05, RSC-RT-05 |
| REQ-21 | Production 구성으로 AZ마다 NAT 1개를 권장하되 공유 구성도 허용한다 | SHOULD | RSC-NAT-06, RSC-NAT-08 |
| REQ-22 | NAT Gateway 대신 NAT 인스턴스·어플라이언스 구성을 지원한다 | MAY | RSC-NAT-07, RSC-ENI-01~11 |
| REQ-23 | VPC Flow Log 를 여러 목적지에 동시에 보낼 수 있다 | MAY | RSC-FLOW-01~08 |
| REQ-24 | EKS 컨트롤러가 요구하는 서브넷 태그를 호출자가 붙일 수 있다 | MAY | [ARCHITECTURE 13절](ARCHITECTURE.md#13-eks-스택) |

---

## 6. 리소스별 요구사항

5절 목표를 리소스 수준에서 확정한 정본이다. ID 는 `RSC-<영역>-<번호>` 이며 코드 주석과 테스트가 이 ID를 가리킨다. 삭제된 ID는 재사용하지 않고 삭제 사실은 [10절](#10-결정-기록)에 남긴다. 별도 표기가 없는 행은 모두 MUST다.

각 행이 전제하는 공통 규칙은 다른 문서가 정의한다. 키 체계·이름·입출력 구조·검사 배치는 [ARCHITECTURE](ARCHITECTURE.md), 태그 병합·수명주기 등 강제 규칙은 [7절](#7-강제-규칙), 결정 배경은 [10절](#10-결정-기록)이다.

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
| RSC-PUB-04 | `shared_public.subnets`의 모든 서브넷은 `gateway = "igw"`인 `0.0.0.0/0` 경로를 가진 Route Table을 가리켜야 한다. 아니면 plan 실패(검사 위치는 ARCHITECTURE 9.1절). IGW Route Table은 호출자가 `route_tables`에 선언하며 모듈이 자동으로 만들지 않는다. |
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
| RSC-NAT-03 | 항목에 `eip_allocation_id`가 있으면 EIP를 만들지 않고 그 allocation을 연결한다. `nat_public_ips` 출력은 EIP 재사용 여부와 무관하게 NAT 리소스의 `public_ip` 속성으로 낸다(ARCHITECTURE 10절). |
| RSC-NAT-06 | 어떤 NAT를 가리키는 경로를 가진 Route Table에 연결된 서브넷의 AZ가 그 NAT의 `public_subnet` AZ와 다르면 Cross-AZ 경로가 된다. 모듈은 이를 허용하되 변수 설명에 비용·장애 영향을 명시한다. |
| RSC-NAT-07 | NAT Gateway 대신 NAT 인스턴스·어플라이언스를 쓰는 구성에서는 `nat_gateways`를 비우고 경로가 ENI를 가리킨다(RSC-RT-01). ENI는 두 방법 중 하나로 정한다. (a) `eni_interfaces`로 모듈이 만들고 경로가 `eni` 키를 적는다(6.6절). 이때 ENI의 서브넷·사설 IP·`source_dest_check`·Security Group은 모듈 입력이다. (b) 호출자가 만든 ENI를 경로가 `network_interface_id`로 가리킨다. 이때 그 ENI가 어느 서브넷에 있는지 모듈이 검사하지 않는다. 어느 방법이든 인스턴스 자체(AMI, 인스턴스 타입, EIP)와 ENI 연결은 이 모듈 범위 밖이다. |
| RSC-NAT-08 | 한 NAT를 여러 Route Table의 경로가 참조할 수 있다. 여러 AZ가 NAT 1개를 공유하려면 각 Route Table의 경로가 같은 `nat_gateway` 키를 적는다. |

### 6.6 Network Interface (ENI)와 Security Group

모듈은 서브넷에 ENI를 만들어 Route Table 경로의 대상으로 쓸 수 있게 하고, 그 ENI에 붙일 Security Group과 그 룰도 만든다. NAT 인스턴스·어플라이언스처럼 호출자가 만드는 인스턴스에 붙일 ENI를 모듈이 먼저 만들어 두면, 인스턴스를 교체해도 경로 대상과 사설 IP, Security Group이 그대로 남는다. 인스턴스와 ENI의 연결만 이 모듈 범위 밖이다(RSC-ENI-08).

| ID | 요구사항 |
| --- | --- |
| RSC-ENI-01 | `eni_interfaces`(선택, 기본 `{}`)는 호출자가 정한 키의 Map이다. 값은 `subnet`(필수), 선택 `private_ips`(`set(string)`), 선택 `security_group_names`(`set(string)`, 기본 `[]`, `security_groups`의 키), 선택 `security_group_ids`(`set(string)`, 기본 `[]`, 호출자가 만든 SG ID), 선택 `source_dest_check`(`bool`, 기본 `true`), 선택 `interface_type`, 선택 `description`, 선택 `tags`(기본 `{}`)를 가진다. 항목마다 `aws_network_interface` 1개를 그 키로 만들며, 어떤 경로도 참조하지 않는 항목도 선언된 대로 만든다(RSC-RT-03과 같은 원칙). |
| RSC-ENI-02 | `subnet`은 이 모듈이 만드는 서브넷의 이름이다(`shared_public.subnets`, `vpc_endpoint_subnets`, 모든 스택 서브넷). 그 서브넷의 ID가 `subnet_id`가 되므로 ENI는 서브넷 생성 뒤에 만들어진다. 존재하지 않는 이름이면 plan 실패(검사 위치는 ARCHITECTURE 9.1절). |
| RSC-ENI-03 | `private_ips`가 `null`이면 AWS가 서브넷 대역에서 자동 할당한다. 값을 주면 `private_ips`에 그대로 전달하며, 서브넷 대역 밖이거나 이미 쓰는 주소면 AWS가 apply에서 거부한다. 모듈은 주소 대역을 검사하지 않는다(RSC-NAT-07과 같은 원칙). |
| RSC-ENI-04 | `source_dest_check`는 기본 `true`다. NAT 인스턴스·어플라이언스용 ENI는 호출자가 `false`로 줘야 하며, `true`인 ENI를 경로 대상으로 쓰면 그 ENI를 지나는 전달 트래픽이 버려진다. 변수 설명에 명시한다. |
| RSC-ENI-05 | ENI에 붙는 Security Group은 `security_group_names`(모듈이 만든 SG의 키)와 `security_group_ids`(호출자가 만든 SG의 ID)의 합집합이며, `aws_network_interface.security_groups`에 그대로 전달한다. 모듈 소유 대상은 키로, 호출자 소유 대상은 ID로 가리키는 원칙을 따른다(RSC-ENI-07과 같다). 둘 다 비어 있으면 `security_groups` 인자를 넘기지 않으며(빈 집합을 넘기지 않는다) AWS가 VPC 기본 SG를 붙인다. 기본 SG는 전면 차단이므로(RSC-DEF-01) 통신이 필요한 ENI는 둘 중 하나를 준다. 변수 설명에 명시한다. |
| RSC-ENI-06 | `interface_type`은 `null`(기본, ENA), `efa`, `efa-only` 중 하나다. AWS 인자 값을 그대로 받고 별칭을 두지 않으며 허용 값 밖이면 plan 실패. AWS가 허용하는 `branch`·`trunk`는 ECS·EKS의 ENI 트렁킹이 쓰는 값이라 컨트롤러가 직접 만들며 이 모듈의 대상이 아니다. 필요해지면 그때 허용 값을 넓힌다. |
| RSC-ENI-07 | 경로가 이 ENI를 가리키는 방법은 `routes`의 `eni`(이 Map의 키)다. 호출자가 만든 ENI는 `network_interface_id`(ID)로 가리키며 둘은 같은 경로 객체에서 택일이다(RSC-RT-01). |
| RSC-ENI-08 | 인스턴스 연결·해제는 모듈 범위 밖이다. 호출자가 출력 `eni_ids`로 `aws_network_interface_attachment`를 만들거나 인스턴스의 `network_interface` 블록에서 참조한다. 인스턴스에 연결된 ENI는 연결을 끊어야 삭제되므로 `eni_interfaces` 항목 제거는 호출자가 연결을 끊은 뒤에 한다. |
| RSC-ENI-09 | ENI가 인스턴스에 연결되기 전에는 그 ENI를 가리키는 경로로 트래픽이 흐르지 않는다. 모듈의 검증은 plan까지이므로([8.1절](#81-명령)) 이 상태는 plan에서 드러나지 않으며, 호출자가 ENI를 연결한 뒤 경로 상태를 확인한다. |
| RSC-ENI-10 | IPv6 주소 옵션(`ipv6_addresses`, `ipv6_address_count` 등), `private_ip_list`, `attachment` 블록, `ena_srd_specification`은 입력에 두지 않는다. 필요하면 호출자가 자기 스택에서 ENI를 만들고 경로에서 `network_interface_id`로 가리킨다. |
| RSC-ENI-11 | `interface_type`이 `efa-only`인 ENI는 IP 트래픽을 다루지 않으므로 경로 대상이나 사설 IP 부여 대상이 아니다. 모듈은 조합을 검사하지 않으며 AWS가 apply에서 거부한다. NAT 용도의 ENI는 `interface_type`을 `null`(ENA)로 둔다. |

Security Group 요구사항은 다음과 같다. 이 절의 SG는 이 모듈이 만드는 ENI에 붙이는 용도이며, 워크로드 SG는 워크로드 모듈이 만든다(ARCHITECTURE 5.1절).

| ID | 요구사항 |
| --- | --- |
| RSC-SG-01 | `security_groups`(선택, 기본 `{}`)는 호출자가 정한 키의 Map이다. 값은 선택 `description`, 선택 `ingress`·`egress`(각각 룰 이름을 키로 하는 Map, 기본 `{}`), 선택 `tags`(기본 `{}`)를 가진다. 항목마다 `aws_security_group` 1개를 그 키로 만들어 이 VPC에 붙이며, 어떤 ENI도 참조하지 않는 항목도 선언된 대로 만든다(RSC-RT-03과 같은 원칙). 이름은 ARCHITECTURE 7절 표의 `<prefix>-<sg_key>-sg`이며 리소스 `name` 인자와 `Name` 태그에 모두 쓴다. `description`이 `null`이면 provider 기본값이 적용되고, 생성 후 `description`을 바꾸면 SG가 재생성된다([7.5절](#75-수명주기-정책)). |
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
| RSC-RT-01 | `route_tables`는 호출자가 정한 키의 Map이다. 값은 선택 `routes`(기본 `{}`), 선택 `propagate_vgw`(`bool`, 기본 `false`), 선택 `tags`(기본 `{}`)를 가진다. `routes`의 키는 목적지 CIDR(IPv4 또는 IPv6)이고 값은 `gateway`, `nat_gateway`, `eni`, `network_interface_id` 네 필드를 가진 객체로, 넷 중 정확히 하나만 `null`이 아니어야 한다. `gateway`는 `igw`·`eigw`·`vgw` 중 하나(validation), `nat_gateway`는 `nat_gateways`의 키, `eni`는 `eni_interfaces`의 키(6.6절), `network_interface_id`는 호출자가 만든 ENI ID(`eni-` 접두어, validation)다. 다음이면 plan 실패: 네 필드가 모두 `null`이거나 둘 이상이 `null`이 아닐 때, `gateway` 값이 허용 값 밖일 때, 목적지가 `vpc_cidr`이나 `secondary_cidrs`와 같을 때(`local` 경로는 AWS가 둔다), `gateway = "vgw"`이거나 `propagate_vgw = true`인데 `vpn_gateway`가 `null`일 때, `gateway = "eigw"`인데 목적지가 IPv4일 때, IPv6 목적지이거나 `gateway = "eigw"`인데 `enable_ipv6 = false`일 때. 검사 위치는 ARCHITECTURE 9.1절. |
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
| RSC-VPCE-01 | `vpc_endpoints.gateway`는 서비스 이름 집합(`s3`, `dynamodb`)이며 Gateway Endpoint를 만들고 RSC-RT-06에 따라 RT에 연결한다. Endpoint 서비스 이름은 Interface Endpoint와 같은 `com.amazonaws.<context.region>.<service>` 형식이므로 `context.region`이 `null`이면 plan 실패(ARCHITECTURE 11절). |
| RSC-VPCE-02 | `vpc_endpoints.interface`는 서비스 이름(`ecr.api` 등)을 키로 하는 Map이며 Endpoint 서비스 이름은 `com.amazonaws.<context.region>.<service>`로 구성한다. `context.region`이 `null`이면 plan 실패(ARCHITECTURE 11절). 값은 선택 `private_dns_enabled`(기본 `true`), 선택 `policy`, 선택 `security_group_names`(기본 `[]`, `security_groups`의 키), 선택 `security_group_ids`(기본 `[]`, 호출자가 만든 SG ID). 두 SG 필드는 ENI와 같은 방식이다(RSC-ENI-05). |
| RSC-VPCE-03 | Interface Endpoint는 `vpc_endpoint_subnets`(RSC-VPCE-07)의 모든 서브넷에 ENI를 만든다. `vpc_endpoints.interface`가 비어 있지 않은데 `vpc_endpoint_subnets`가 비어 있으면 plan 실패. |
| RSC-VPCE-04 | Interface Endpoint에 붙는 SG는 `security_group_names`(모듈 SG)와 `security_group_ids`(호출자 SG)의 합집합이다. 둘 다 비어 있는 Interface Endpoint가 1개 이상이면 모듈이 Endpoint 전용 SG 1개를 만들어 그 Endpoint들에만 붙이고, VPC CIDR과 보조 CIDR에서 443 인바운드만 허용하며, `enable_ipv6 = true`이면 VPC의 IPv6 CIDR(`aws_vpc`의 `ipv6_cidr_block` 속성)에서의 443 인바운드도 함께 허용한다. 모든 Interface Endpoint가 SG를 지정했거나 Interface Endpoint가 없으면 전용 SG를 만들지 않으며 `vpc_endpoint_security_group_id` 출력은 `null`이다(ARCHITECTURE 10절). |
| RSC-VPCE-07 | `vpc_endpoint_subnets`(ARCHITECTURE 2.3절 서브넷 Map, 선택, 기본 `{}`)는 Interface VPC Endpoint ENI 배치 전용 서브넷이다. 워크로드는 여기 두지 않고 `stack_subnets`의 스택으로 정의한다(ARCHITECTURE 5.1절). 각 서브넷은 기본 경로(`0.0.0.0/0`, `::/0`)가 없는 Route Table을 가리켜야 하고 같은 `az` 값을 가진 서브넷이 2개 이상이면 안 된다(Interface Endpoint는 AZ당 서브넷 1개만 받는다). 위반 시 plan 실패(검사 위치는 ARCHITECTURE 9.1절). 정의하지 않으면 관련 리소스가 0개다. |

### 6.11 VPN Gateway와 Customer Gateway

| ID | 요구사항 |
| --- | --- |
| RSC-VPN-01 | `vpn_gateway` 객체가 `null`이 아니면 VGW를 만든다. 값은 선택 `amazon_side_asn`(기본 `null`. `null`이면 AWS 기본값 `64512`가 적용된다), 선택 `availability_zone`(AZ 이름. ARCHITECTURE 2.3절의 예외), 선택 `existing_id`. 경로 전파 대상은 각 Route Table의 `propagate_vgw`가 정하며 `propagate_to` 입력은 두지 않는다. |
| RSC-VPN-02 | `vpn_gateway.existing_id`가 있으면 새로 만들지 않고 `aws_vpn_gateway_attachment`(단일 리소스, ARCHITECTURE 6절)로 이 VPC에 연결한다. Route Table의 `propagate_vgw`는 새로 만들 때와 `existing_id`를 쓸 때 모두 허용한다. `existing_id`와 함께 `amazon_side_asn` 또는 `availability_zone`을 `null`이 아닌 값으로 주면 plan 실패. |
| RSC-VPN-03 | 경로 전파 리소스는 RSC-RT-11이 정의한다. VGW 정적 경로가 필요하면 그 Route Table의 `routes`에 `gateway = "vgw"` 항목을 적는다. |
| RSC-VPN-04 | `customer_gateways`는 키 Map이며 값은 `bgp_asn`, `ip_address`(필수), 선택 `device_name`, 선택 `tags`(기본 `{}`). `type`은 `ipsec.1` 고정. |
| RSC-VPN-05 | VPN Connection 자체는 이 모듈 범위 밖이다. 출력 `vgw_id`, `cgw_ids`로 상위 모듈이 연결한다. |

### 6.12 VPC Flow Logs

`aws_flow_log`은 목적지를 하나만 갖는다. 같은 VPC를 여러 목적지에 동시에 보내려면 목적지 수만큼 Flow Log를 만들어야 하므로, 입력은 목적지 이름을 키로 하는 평면 Map으로 받고 항목마다 리소스 1개를 만든다. 목적지 리소스(로그 그룹, 버킷, Delivery Stream)와 그 IAM 롤·버킷 정책·KMS 키 정책은 모듈 범위 밖이며 ARN으로만 참조한다(RSC-FLOW-08).

| ID | 요구사항 |
| --- | --- |
| RSC-FLOW-01 | `flow_logs`(선택, 기본 `{}`)는 호출자가 정한 키의 Map이며 항목마다 `aws_flow_log` 1개를 그 키로 만든다. 항목을 빼면 그 Flow Log만 사라지고 나머지는 그대로다. 빈 Map이면 Flow Log가 0개다. 목적지를 한 겹 더 감싸는 객체를 두지 않으며, 빈 Map이 0개를 뜻하는 것은 `nat_gateways`·`eni_interfaces`와 같은 관례다(DEC-105). |
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

출력 요구사항 RSC-OUT-01·04·06 과 출력 표는 계약이므로 [ARCHITECTURE 10절](ARCHITECTURE.md#10-출력-계약)에 둔다.

---

## 7. 강제 규칙

6절 리소스별 요구사항이 전제하는 공통 규칙이다. 조직 표준을 기본값으로 제공하고, 예외가 필요한 설정에만 명시적 Override 인터페이스를 두는 것이 이 절 전체의 원칙이다. 코드가 이 규칙을 어떻게 구현하는지는 [ARCHITECTURE 12절](ARCHITECTURE.md#12-코드-컨벤션)이, 입력 검증을 어디에 두는지는 [ARCHITECTURE 9절](ARCHITECTURE.md#9-입력-검증과-검사-배치)이 정의한다.

### 7.1 Convention over Configuration

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

반대로 **선언해야만 생기는** 것은 Route Table 과 경로, NAT, ENI·SG, NACL, Endpoint, VGW·CGW, Flow Log, Private DNS, DHCP 다. 비용이 크거나 보안 경계를 바꾸는 리소스를 암묵적으로 만들지 않기 위해서다([7.6절](#76-비용-정책)).

### 7.2 이름 정책

이름 규칙 표의 정본은 [ARCHITECTURE 7절](ARCHITECTURE.md#7-이름-규칙)이다. 이 절은 그 표를 강제하는 규칙만 적는다.

- 이름 접두어는 `context.name_prefix` 하나에서만 온다. 접두어를 덮어쓰는 입력을 두지 않는다.
- 모듈은 스택·AZ를 조합해 이름을 만들어 내지 않는다. `<이름>` 자리에는 호출자가 정한 마지막 마디만 들어간다.
- 호출자가 정하는 이름 키에는 소문자·숫자·`-` 만 허용하고, 예약 키(`shared-` 로 시작하는 스택 키, Security Group 키 `vpce`)를 금지한다. 위반은 plan 실패다.
- 리소스 `name` 인자로 쓰이는 이름은 `context.name_prefix` 길이에 따라 AWS 제약(가장 짧은 것은 IAM 롤 64자)을 넘을 수 있다. 모듈은 길이를 검사하지 않고 그 사실을 변수 `description` 에 적는다.
- 리소스 키 산식이나 이름 규칙을 바꾸면 배포된 리소스가 재생성된다. [7.7절](#77-버전과-호환성)의 MAJOR 규칙을 따른다.

### 7.3 태그 정책

모든 리소스의 태그는 아래 두 출처를 이 순서로 병합하고 마지막에 `Name`을 붙인다. 뒤 단계가 앞 단계의 같은 키를 덮어쓴다. 병합 순서의 일반 규칙은 [ARCHITECTURE 12절](ARCHITECTURE.md#12-코드-컨벤션)이 정의하며, 이 절은 이 모듈의 어떤 입력이 각 단계에 들어가는지를 정한다. 다른 요구사항 문서는 이 절을 참조하고 병합 대상을 다시 정의하지 않는다.

```text
tags = merge(context.tags, <사용자 커스텀 tags>, { Name = <이름> })
```

| 순서 | 출처 | 내용 | 필수 여부 |
| --- | --- | --- | --- |
| 1 | `context.tags` | 조직 공통 태그. 모든 리소스의 기반 | 필수(`context`의 일부) |
| 2 | 사용자 커스텀 `tags` | 모듈 공통 `tags` → 스택 `tags` 또는 `shared_public.tags` → 서브넷 `tags` → Route Table·NAT·ENI·SG·CGW 인스턴스별 `tags`. 같은 단계 안에서는 이 나열 순서대로 뒤가 앞을 덮어쓴다 | 선택. 각각 기본 `{}` |

리소스별로 보면 아래처럼 자기 인스턴스의 `tags`만 더한다. 각 커스텀 `tags`가 어느 리소스에 적용되는지는 7.3.1절이 정의한다.

```hcl
resource "aws_nat_gateway" "this" {
  tags = merge(context.tags, var.tags, var.nat_gateways[each.key].tags, { Name = "..." })
}
```

- 모듈이 만드는 태그는 `Name` 하나이며 병합 마지막에 붙인다. `ManagedBy`, `Environment` 등 조직 공통 키는 `context.tags`로 들어오므로 모듈이 다시 만들지 않는다.
- 보호 키: `Name`은 커스텀 `tags`에 포함될 수 없다. 포함되면 plan이 실패해야 한다. 그 외의 키(예: `kubernetes.io/*`, `karpenter.sh/*`)는 호출자가 자유롭게 정의하며 모듈이 생성·검사하지 않는다.
- `context.tags`의 키는 보호 키가 아니다. 커스텀 `tags`로 덮어쓸 수 있다.
- 태그의 용도(비용 배부, 조직 식별 등)는 호출자가 정한다. 모듈은 특정 용도의 태그 키를 요구하거나 검사하지 않으며 태그 용도를 위한 별도 입력을 두지 않는다.

#### 7.3.1 각 태그 입력이 적용되는 리소스

태그 병합 순서와 보호 키는 7.3절을 따르며 여기서 다시 정의하지 않는다. 이 절은 각 커스텀 `tags` 입력이 어느 리소스에 적용되는지만 정한다.

- 인스턴스별 커스텀 `tags`(7.3절 2단계)는 스택, Shared Public, 서브넷, Route Table, NAT, ENI, Security Group, CGW가 가진다. 스택 `tags`는 그 스택의 모든 서브넷, NACL, 네 종류의 Subnet Group에 적용되고, 서브넷 `tags`는 그 서브넷 하나에, Route Table `tags`는 그 RT에, `nat_gateways.<key>.tags`는 그 NAT와 EIP에, `eni_interfaces.<key>.tags`는 그 ENI에, `security_groups.<key>.tags`는 그 SG와 그 SG의 룰 리소스에 적용된다(RSC-SG-06). 스택 서브넷에 적용되는 순서는 스택 `tags` → 서브넷 `tags`다.
- Shared Public은 `shared_public.tags`가 그 아래 모든 서브넷과 Shared Public NACL에 적용되고, 서브넷 `tags`가 그다음이다. `vpc_endpoint_subnets`는 서브넷 `tags`만 가진다.
- 모듈 공통 `tags`는 모듈이 만드는 모든 리소스에 적용된다. Flow Log, Endpoint 전용 SG, SG 룰처럼 자기 인스턴스 `tags`가 없는 리소스는 `context.tags`와 모듈 공통 `tags`(룰은 그 SG의 `tags`도)를 받는다.

### 7.4 Security by Default

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

### 7.5 수명주기 정책

이 절이 수명주기 원칙의 유일한 정의다. 리소스별 요구사항은 이 절을 참조하고 다시 서술하지 않는다.

- 어떤 키의 항목을 추가·제거하든 그 키의 리소스만 생성·삭제하며, 다른 키의 plan 결과는 변경(`~`)·재생성(`-/+`) 0건이어야 한다. 대상은 스택, 서브넷, Route Table과 그 경로, NAT, ENI, Security Group과 그 룰, NACL과 룰, Secondary CIDR, VPC Endpoint, CGW, VGW 전파, 네 종류의 Subnet Group, 서브넷 `tags`다. IGW와 Egress-only IGW는 경로 대상에서 파생되는 단일 리소스이므로(RSC-PUB-05, RSC-RT-05) 그 대상을 쓰는 경로를 처음 추가할 때 생성되고 마지막으로 제거할 때 삭제되는 것은 이 규칙의 예외다.
- 스택 제거 시 그 스택의 서브넷, NACL, 네 종류의 Subnet Group만 삭제된다. 가리키는 서브넷이 없어진 Route Table과 NAT는 그대로 남는다(RSC-RT-03).
- 경로의 대상을 바꾸면 그 경로 1개만 교체된다. NAT의 생성·삭제는 `nat_gateways` 항목의 추가·제거가 정하며 경로가 참조를 끊는 것만으로는 NAT가 사라지지 않는다. 마지막 `gateway = "igw"` 경로를 지우면 IGW가, 마지막 `gateway = "eigw"` 경로를 지우면 Egress-only IGW가 함께 삭제된다(첫 항목의 예외).
- 서브넷의 `route_table` 값 변경은 서브넷 재생성이 아니라 Association 교체다(RSC-RT-09).
- Security Group 룰은 키(룰 이름)나 소속 SG가 바뀌면 교체되고, `ip_protocol`·포트·소스·`description`은 그 룰 리소스 안에서 갱신된다. provider가 룰 리소스의 이 필드들을 `ModifySecurityGroupRules`로 수정하므로 룰을 다시 만들지 않아 통신 단절이 없다.
- 생성 후 변경이 곧 재생성을 뜻하는 입력(`vpc_cidr`, 서브넷 이름·`cidr`·`az`, 스택 키, Route Table 키, NAT 키, NAT의 `public_subnet`, ENI 키, ENI의 `subnet`·`private_ips`, Security Group 키, SG의 `description`)은 변수 설명에 "변경 시 재생성"을 명시하고, 필요하면 호출자가 `moved` 블록을 쓰도록 안내한다.

### 7.6 비용 정책

비용이 큰 리소스를 암묵적으로 만들지 않고, 비용이 드는 선택을 변수 설명으로 드러낸다.

| 리소스 | 정책 |
| --- | --- |
| NAT Gateway | `nat_gateways` 에 선언한 만큼만 만든다. 입력이 비면 0개다. 여러 Route Table 이 한 NAT 를 참조할 수 있어 경로를 나눠도 NAT가 늘지 않는다(RSC-NAT-08) |
| Cross-AZ 트래픽 | 서브넷 AZ와 NAT의 `public_subnet` AZ가 다르면 Cross-AZ 경로가 된다. 모듈은 허용하되 변수 설명에 비용·장애 영향을 명시한다(RSC-NAT-06) |
| EIP | NAT 항목마다 1개를 만들되 `eip_allocation_id` 로 기존 EIP를 재사용할 수 있다(RSC-NAT-03) |
| Interface Endpoint | `vpc_endpoints.interface` 에 적은 서비스만 만든다. AZ마다 ENI가 생기므로 `vpc_endpoint_subnets` 수가 곧 ENI 수다 |
| Flow Log | `flow_logs` 가 비면 0개다. 목적지 하나가 Flow Log 하나이므로 항목을 더하면 그만큼 요금이 붙는다(RSC-FLOW-01) |
| 로그 보존·스토리지 | 목적지 리소스를 모듈이 만들지 않으므로 보존 기간과 스토리지 비용은 그 리소스를 소유한 스택이 정한다(RSC-FLOW-08) |
| Public IPv4 | 서브넷 자동 할당을 끄고(RSC-PUB-01) 공인 IP는 EIP나 AWS 관리 IP로 제한한다 |

### 7.7 버전과 호환성

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

MAJOR 변경은 사용자에게 먼저 알리고, 이전 버전 사용자가 무엇을 고쳐야 하는지 [10절](#10-결정-기록)에 남긴다.

### 7.8 Anti-Patterns

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

---

## 8. 검증과 테스트

### 8.1 명령

| 구분 | 명령 | 비고 |
| --- | --- | --- |
| 포맷 | `terraform fmt -check *.tf` (로컬에 `tests/` 가 있으면 `terraform fmt -check -recursive tests/` 도) | 적용 범위는 [ARCHITECTURE 12절](ARCHITECTURE.md#12-코드-컨벤션) 마지막 항목. `examples/` 는 대상이 아니다 |
| 검증 | `terraform init -backend=false && terraform validate` | 루트에서 실행 |
| 계획 | `cd examples/<이름> && terraform init && terraform plan` | 8.2절 3단계. AWS 자격 증명 필요, 읽기 전용 |
| 테스트 | `terraform test -filter=tests/<대상>.tftest.hcl -var-file=requirements/<기준 입력>.tfvars -var-file=tests/context.tfvars` | 루트에서 실행. 8.2절 4단계 |

`terraform apply` 와 `terraform destroy` 는 루트와 `examples/` 어디서도 실행하지 않는다. 검증은 `validate` 와 `plan`, 그리고 `mock_provider` 아래의 `terraform test` 까지다. 테스트의 `command = apply` 는 mock 상태에만 쓰고(8.2절 4단계) AWS 를 호출하지 않으므로 이 금지의 대상이 아니다.

### 8.2 절차

테스트는 **모듈 루트의 `tests/*.tftest.hcl`** 에 작성해 루트에서 `terraform test` 로 실행한다. `examples/<이름>/` 은 `plan` 전용 검증 스택으로 남긴다. `tests/`·`examples/` 와 기준 입력 파일은 모두 `.gitignore` 로 제외된 로컬 검증 자산이며(이 문서 머리말의 주제별 정의 위치) 저장소에는 그것을 정의하는 이 절과 8절만 남는다. 테스트를 `examples/` 에 두면 `assert` 가 자식 모듈(`module "vpc"`)의 리소스에 닿지 않아 출력으로 드러나는 항목만 검증할 수 있기 때문이다. `CLAUDE.md` 필수 작업 지침 4항의 Mock 테스트와 회귀 테스트는 아래 4단계의 `run` 블록으로 대신한다.

1. 수정한 파일에 `terraform fmt` 를 적용한다. 검증용 임시 스택 `examples/` 는 대상이 아니므로 `-recursive` 를 루트 전체에 쓰지 않는다([ARCHITECTURE 12절](ARCHITECTURE.md#12-코드-컨벤션) 마지막 항목).
2. 루트에서 `terraform init -backend=false && terraform validate` 를 통과시킨다.
3. `examples/<이름>/` 에 `provider "aws"` 블록과 `module "<이름>" { source = "../../" ... }` 호출을 담은 임시 스택을 만들고, 검증 대상 입력(8.4절)을 `-var-file` 로 넣어 `terraform init && terraform plan` 을 실행한다. 스택이 이미 있으면 새로 만들지 않고 그 스택에 변경 내용을 반영한다.
4. `tests/<검증 대상>.tftest.hcl` 에 `run` 블록을 작성하고 루트에서 `terraform test` 로 실행한다. 작성 규칙은 아래와 같다.
   - 파일마다 `mock_provider "aws" {}` 를 선언한다(Terraform 1.7 이상). AWS 를 호출하지 않으므로 자격 증명이 필요 없고 리소스도 만들어지지 않는다. 자격 증명이 필요한 `data` 소스는 `override_data` 로 대체한다.
   - `mock_provider` 를 선언한 파일의 `run` 은 `command = apply` 를 쓸 수 있다. `command = plan` 에서는 리소스 ID 가 미확정이라 "경로의 `nat_gateway_id` 가 그 키의 NAT" 처럼 리소스끼리 참조하는 값을 비교할 수 없기 때문이다. 입력 검증만 보는 `run`(실패 케이스 등)은 `command = plan` 으로 둔다.
   - 기준 입력은 `-var-file` 로 넣는다. 다섯 기준 입력의 구성은 8.4절이 정의하며 관례상 `requirements/<이름>.tfvars` 로 만든다. 그 뒤에 해석된 `context` 객체를 담은 `tests/context.tfvars` 를 붙여 모듈 입력을 완성한다. 뒤에 오는 var-file 이 앞을 덮어쓰므로 순서를 바꾸지 않는다. 기준 입력에만 있는 `module "ctx"` 용 키(`team`, `cost_center`)는 경고만 남기고 무시된다.
   - `variables` 블록으로 입력을 주고 `assert` 로 리소스 수, `Name` 태그, 리소스 인자, Map 키가 의도와 같은지 검증한다. 검증 대상마다 파일을 나눈다.
   - provider 스키마에서 Optional+Computed 인 속성은 `mock_provider` 가 임의 값으로 채우므로 `null` 단언의 대상이 아니다. 그 속성이 비었음을 봐야 하면 함께 설정되는 관찰 가능한 속성으로 대신 검증하고, 대체할 속성이 없으면 그 한계를 테스트 파일 주석에 남긴다.
   - [ARCHITECTURE 12.3절](ARCHITECTURE.md#123-terraform-설계-원칙)의 멱등성 원칙 검증으로, 항목을 하나 추가한 입력과 제거한 입력을 각각 `run` 으로 두고 기존 키의 리소스가 같은 키·같은 속성으로 남는지 `assert` 한다. 이전 상태와의 diff 는 5단계에서 본다.
   - 한 파일 안의 `run` 은 상태를 공유한다. `apply` 한 `run` 뒤의 `run` 은 그 결과 위에서 실행되므로 독립적으로 봐야 하는 검증은 파일을 나눈다.
   - 버그를 수정할 때는 재현하는 `run` 블록을 먼저 추가해 실패를 확인한 뒤 모듈을 고친다.
5. plan 판정 기준: 입력 변수 추가나 기본값 유지 변경은 기존 호출에서 변경(`~`)이나 재생성(`-/+`)이 0건이어야 한다. 1건이라도 있으면 원인을 설명하고 사용자 판단을 받는다. `terraform test` 에는 이전 상태와의 diff 를 `assert` 로 보는 수단이 없으므로, "기존 리소스 변경 0건" 류의 항목은 4단계가 아니라 이 3·5단계의 `plan` 결과로 판정한다(8.5절 판정 열).
6. 새 입력 변수를 추가했으면 3단계 호출 스택에 그 변수를 넣어 plan 결과에 의도한 리소스만 추가되는지 확인하고, 4단계에 그 변수를 검증하는 `run` 블록을 추가한다.

### 8.3 Terraform 버전

모듈의 `required_version` 하한은 `>= 1.5.7` 이다. 이 값은 재구현 뒤 `versions.tf` 에 적히지만 근거는 이 절이며, [ARCHITECTURE 9.2절](ARCHITECTURE.md#92-검사-배치)의 `validation`·`precondition` 분류가 이 하한에 걸려 있으므로(다른 변수를 참조하는 `validation` 은 1.9 이상 기능) 하한을 올리거나 내리면 그 절을 함께 고친다.

`mock_provider` 가 Terraform 1.7 이상을 요구하므로 테스트에 한하여 1.7 이상 버전을 사용한다. 테스트는 모듈의 `required_version` 하한과 무관한 검증 절차이므로 하한은 올리지 않고 테스트를 실행하는 Terraform CLI 만 1.7 이상을 쓴다. 쓸 수 있는 CLI 가 `required_version` 하한과 같아 `mock_provider` 를 지원하지 않으면 8.2절 4단계를 건너뛰고 그 사실을 결과 보고에 적는다.

모듈이 의존하는 tfmodule-context 의 참조 버전은 `v1.3.5` 이상이며 이 제약의 유일한 정의는 [ARCHITECTURE 11절](ARCHITECTURE.md#11-context-계약)이다. 이 모듈은 참조 버전을 코드로 강제하지 않으므로(모듈 안에 원격 모듈 버전을 검사하는 로직을 두지 않는다, [ARCHITECTURE 12절](ARCHITECTURE.md#12-코드-컨벤션)) 위반은 리뷰와 검증 결과로 잡는다. `module "ctx"` 를 선언하는 `examples/` 스택과 `tests/context.tfvars` 를 만들 때 `source` 의 `?ref=` 가 `v1.3.5` 이상의 태그인지 확인한다. `v1.3.5` 미만을 참조하면 이 모듈이 쓰는 `name_prefix`·`tags`·`region`·`pri_domain` 등 출력 필드의 스키마가 달라 `context` 타입이 값을 조용히 버리거나 다른 뜻으로 읽으므로, `terraform validate`·`plan` 이 실패하거나 태그가 조용히 누락되는 것으로도 위반이 드러난다.

### 8.4 기준 입력

검증에는 다섯 가지 기준 입력을 쓴다. 이 절이 그 구성의 유일한 정의다. 파일 자체는 저장소에 두지 않는 로컬 검증 자산이며(이 문서 머리말의 주제별 정의 위치) 관례상 `requirements/<이름>.tfvars`로 만든다. 8.5절 표의 **기준 입력** 열은 아래 표의 이름을 가리킨다.

기준 입력은 `examples/` 검증 스택과 `terraform test` 가 함께 쓴다. 두 쓰임의 차이(`module "ctx"` 유무, `tests/context.tfvars` 결합)는 이 문서 머리말의 주제별 정의 위치가 정의하며, "모듈 대상 키"는 `context`, `team`, `cost_center`를 제외한 최상위 키를 뜻한다.

| 이름 | AZ | 담아야 하는 것 |
| --- | --- | --- |
| `basic` | 2 | 최소 구성의 기준값. Shared Public, 워크로드 스택 1개, AZ별 NAT 1개, `igw`·NAT·경로 없음 세 종류의 Route Table, DB·ElastiCache Subnet Group, S3 Gateway Endpoint, Private Hosted Zone, 모듈 공통 `tags`. `enable_ipv6`는 `false` |
| `full` | 2 | `basic`의 모든 항목에 더해 스택 전용 Public, 격리 서브넷, 보조 CIDR, 온프레미스 전용 계층, EIP 재사용, NAT 인스턴스 ENI 경로(`eni_interfaces`와 호출자 ENI 두 방식을 각각 실제 서브넷이 쓴다), `security_groups`와 룰, `shared_public.nacl`, 스택 NACL, Redshift·MemoryDB Subnet Group, VGW·CGW, DHCP, `flow_logs` 항목 1개(`s3`), Interface Endpoint와 `vpc_endpoint_subnets` |
| `basic_ipv6` | 2 | `basic` + IPv6(`enable_ipv6 = true`, 일부 서브넷의 `ipv6_index`, `::/0` 경로와 Egress-only IGW) |
| `full_ipv6` | 2 | `full` + IPv6. 위에 더해 IPv6 NACL 룰과 예약 값 `vpc`를 담는다 |
| `eks` | 3 | [ARCHITECTURE 13.3절](ARCHITECTURE.md#133-예시)의 EKS 참조 구성. 스택 5개(`svc`, `auction`, `cms`, `toolchain`, `obsv`), 스택 NACL 1개, 스택별 DB Subnet Group, Interface Endpoint, `flow_logs` 항목 2개(`cloud-watch-logs` + `s3`) |

- 항목 추가·제거를 보는 검증은 `basic`에서 한 항목을 더하거나 뺀 입력으로 만든다. `run` 블록의 `variables`로 그 항목만 덮어쓰는 방식을 쓴다.
- `basic`에 없는 기능은 `full`을 기준값으로 하거나 `basic`에 그 기능 입력만 더한 `variables`로 만든다.
- IPv4 기준 입력과 그 IPv6 짝은 IPv6 입력 외에 모든 값이 같아야 한다. 두 파일의 plan 차이가 IPv6 관련 리소스·속성에 한정되는 것이 TST-25·26의 전제다.
- `eks`는 3 AZ·스택 5개 구성의 회귀용이며 TST-37·TST-39만 쓴다. `flow_logs` 다중 항목은 이 입력에만 있다. 다른 항목의 기준값으로 쓰지 않는다.
- 기준 입력에 항목을 더하거나 빼면 이 표와 8.5절의 해당 행을 같은 변경에서 갱신한다.

### 8.5 검증 항목

아래 표가 `terraform test` 검증 항목의 유일한 정의다. 한 행이 `run` 블록 하나 이상에 대응하며, 테스트 파일은 검증 대상별로 나눈다(8.2절 4단계). 항목을 더하거나 바꾸면 근거 요구사항과 같은 변경에서 이 표를 갱신한다.

| ID | 기준 입력 | 검증 내용 | 근거 | 판정 |
| --- | --- | --- | --- | --- |
| TST-01 | IPv4·IPv6 기준 입력 4종 | 모듈 대상 키와 `stack_subnets` 항목의 모든 필드가 모듈 변수 타입에 존재한다. Terraform은 `object` 타입에 없는 속성을 오류 없이 버리고 `assert`는 변수 타입을 직접 볼 수 없으므로, 필드마다 그 필드가 만드는 리소스 속성 1개 이상을 검증한다. 예: `memorydb_subnet_group` → `aws_memorydb_subnet_group` 수, 서브넷 `tags` → 그 서브넷 태그, `tags.Platform` → 모든 리소스 태그 | ARCHITECTURE 8.1절 | test |
| TST-02 | basic + 스택 1개 | 스택 1개 추가 시 plan 결과가 그 스택 키의 리소스 생성만 포함하고, 서브넷 키가 `<stack>/<name>` 형식이다 | ARCHITECTURE 6절, [7.5절](#75-수명주기-정책) | test + plan |
| TST-03 | basic − 스택 1개 | 스택 1개 제거 시 plan 결과가 그 스택 키의 리소스 삭제만 포함한다 | [7.5절](#75-수명주기-정책) | test + plan |
| TST-04 | basic ± 서브넷 1줄 | 스택 서브넷 1줄을 새 AZ로 추가해도 기존 리소스 변경 0건. 서브넷 1줄의 `tags`를 더하거나 빼도 다른 서브넷과 다른 스택의 plan 변경 0건 | [7.5절](#75-수명주기-정책) | test + plan |
| TST-05 | basic + RT 1개 | 어떤 서브넷도 가리키지 않는 `route_tables` 항목 1개를 더해도 plan이 실패하지 않고 그 RT와 그 경로(Gateway Endpoint 연결 포함, 첫 `igw`·`eigw` 대상이면 7절 예외대로 IGW·Egress-only IGW)만 생성되며 기존 리소스 변경 0건 | RSC-RT-03, [7.5절](#75-수명주기-정책) | test + plan |
| TST-06 | basic − 스택 1개 | 스택 1개를 제거하면서 그 스택만 가리키던 RT를 남겨도 RT·NAT 변경 0건 | RSC-RT-03, [7.5절](#75-수명주기-정책) | test + plan |
| TST-07 | basic, full | Route Table 수가 `route_tables` 항목 수와 같고 경로 수가 모든 `routes` 항목 수의 합과 같다 | RSC-RT-01, RSC-RT-02 | test |
| TST-08 | basic, full | NAT 수가 `nat_gateways` 항목 수와 같고, 각 NAT가 `public_subnet`이 가리키는 Shared Public Subnet에 있다 | RSC-NAT-01, RSC-NAT-02 | test |
| TST-09 | basic, full | 각 경로의 대상 속성이 입력과 대응한다. `gateway = "igw"` → `gateway_id`가 IGW, `eigw` → `egress_only_gateway_id`, `vgw` → `gateway_id`가 VGW, `nat_gateway = "<키>"` → 그 키의 NAT, `eni = "<키>"` → 그 키의 ENI, `network_interface_id` → 입력값 그대로. 나머지 대상 속성은 `null`이다 | RSC-RT-01, RSC-RT-02 | test |
| TST-10 | basic, full | `gateway = "igw"` 경로가 1개 이상이면 IGW 1개가 있고 없으면 0개다. `gateway = "eigw"`와 Egress-only IGW도 같다 | RSC-PUB-05, RSC-RT-05 | test |
| TST-11 | basic, full | 각 서브넷의 Association이 가리키는 Route Table이 그 서브넷 항목의 `route_table` 값과 같고, 서브넷 수가 `shared_public.subnets` + `vpc_endpoint_subnets` + 모든 스택 서브넷의 합과 같다 | RSC-RT-09, ARCHITECTURE 2.3절 | test |
| TST-12 | basic + `route_table` 변경 | 서브넷의 `route_table` 값만 바꾸면 그 서브넷은 재생성되지 않고 Association 1건만 교체된다 | RSC-RT-09, [7.5절](#75-수명주기-정책) | test + plan |
| TST-13 | basic | 한 NAT를 두 Route Table의 경로가 함께 참조해도 plan이 실패하지 않고 NAT는 1개다 | RSC-NAT-08 | test |
| TST-14 | basic | 기본 NACL에 IPv4·IPv6 전체 허용 ingress·egress 룰이 있다 | RSC-DEF-03 | test |
| TST-15 | basic, full | 모든 리소스의 `Name` 태그가 ARCHITECTURE 7절 표와 일치한다. 예: 서브넷 `blb-a1` → `<prefix>-blb-a1-sn`, RT `pri-a1` → `<prefix>-pri-a1-rt`, NAT 키 `a1` → `<prefix>-a1-nat` | ARCHITECTURE 7절 | test |
| TST-16 | basic | `routes`가 비어 있는 RT에 `aws_route`가 0개이고, 그 RT를 가리키는 서브넷에는 인터넷 방향 경로가 없다 | RSC-RT-01 | test |
| TST-17 | basic + 서브넷 1줄 | 데이터 계층 이름의 스택 서브넷이 `igw` 경로를 가진 RT를 가리켜도 plan이 실패하지 않는다 | ARCHITECTURE 2.2절 | test |
| TST-18 | full | `eip_allocation_id`를 준 NAT는 `aws_eip`를 만들지 않고 `nat_eip_allocation_ids`의 그 키 값이 입력값과 같다 | RSC-NAT-03 | test |
| TST-19 | full | `gateway = "igw"` 경로를 가진 RT를 가리키는 스택 서브넷에 스택 `tags`가 적용되고 `map_public_ip_on_launch = false`다 | RSC-PUB-03 | test |
| TST-20 | full | 격리 서브넷의 CIDR이 보조 CIDR 대역 안에 있고 `vpc_secondary_cidr_association_ids`에 그 CIDR 키가 있다 | RSC-VPC-02 | test |
| TST-21 | full | `network_interface_id` 대상 경로의 `network_interface_id`가 입력값과 같다 | RSC-NAT-07, RSC-RT-01 | test |
| TST-22 | full | `flow_logs`에 항목 1개(`s3`)를 선언하면 `aws_flow_log`가 1개이고 키가 그 항목 키다. `log_destination`·`log_destination_type`이 입력과 같고 `iam_role_arn`이 `null`이며, `destination_options`가 `parquet`·Hive 파티션·시간별 파티션이다. 모듈이 만드는 로그 그룹·IAM 롤 리소스는 없다 | RSC-FLOW-01·02·05·08 | test |
| TST-23 | full | VGW 전파 리소스 수가 `propagate_vgw = true`인 RT 수와 같고 키가 RT 키와 같다 | RSC-RT-11 | test |
| TST-24 | full | NACL 룰 리소스 수가 두 NACL의 `ingress`·`egress` 룰 수의 합과 같다 | RSC-NACL-02 | test |
| TST-25 | basic_ipv6 | VPC가 Amazon 제공 IPv6 /56을 받고, `ipv6_index`가 있는 서브넷만 IPv6 CIDR과 `assign_ipv6_address_on_creation = true`를 갖는다. `ipv6_cidr_block`은 Optional+Computed라 `null` 단언의 대상이 아니므로(9절 도입부) 값이 없는 서브넷은 `assign_ipv6_address_on_creation = false`로 확인한다. basic.tfvars 대비 plan 차이가 VPC IPv6 속성, 서브넷 IPv6 속성, Egress-only IGW, `::/0` 경로에 한정된다 | RSC-VPC-05 | test + plan |
| TST-26 | full_ipv6 | `ipv6_cidr_block`을 준 룰은 `cidr_block`이 `null`이고 `::/0` 룰은 `ipv6_cidr_block`이 입력값이다. 예약 값 `vpc` 룰은 리소스가 존재하고 `cidr_block`이 `null`이다. full.tfvars 대비 NACL 룰 수 차이가 `ipv6_cidr_block` 룰 수와 같다 | RSC-NACL-05, RSC-NACL-06 | test + plan |
| TST-27 | full | 태그가 [7.3절](#73-태그-정책) 순서로 병합된다. 같은 키를 `context.tags`와 모듈 `tags`에 다른 값으로 넣으면 모듈 `tags` 값이 남고, 스택 `tags`가 그 스택의 서브넷·NACL·DB Subnet Group·ElastiCache Subnet Group에만 적용되며, 서브넷 `tags`(`kubernetes.io/*`, `karpenter.sh/*` 포함)가 그 서브넷 하나에만 적용되고 같은 스택의 다른 서브넷에는 없다 | [7.3절](#73-태그-정책), [7.3.1절](#731-각-태그-입력이-적용되는-리소스) | test |
| TST-28 | basic, full | 모든 출력이 키 Map 또는 `null` 가능 단일 값이며 ARCHITECTURE 10절 출력 표의 항목이 모두 존재하고, `stacks.<stack>.subnet_ids`의 키가 그 스택 서브넷 이름과 일치한다 | RSC-OUT-01, RSC-OUT-04, RSC-OUT-06 | test |
| TST-29 | basic + `nat_gateways = {}` + 기본 경로를 `eni`로 교체 | `nat_gateways`를 비우고 `pri-*` RT의 기본 경로를 `eni_interfaces`의 ENI로 바꾼 입력에서 plan이 실패하지 않고 `aws_nat_gateway`와 `aws_eip`가 0개다. 같은 방식으로 `network_interface_id`(호출자 ENI)로 바꾼 입력도 확인한다 | RSC-NAT-07, RSC-RT-01, RSC-ENI-07 | test |
| TST-30 | full_ipv6 | 모듈이 만든 Endpoint 전용 SG에 VPC IPv4·보조 CIDR의 443 인바운드와 VPC IPv6 CIDR의 443 인바운드가 모두 있다 | RSC-VPCE-04 | test |
| TST-31 | full | `eni_interfaces` 항목마다 `aws_network_interface` 1개가 그 키로 만들어지고, `subnet_id`가 `subnet` 이름의 서브넷이며 `private_ips`·`source_dest_check`·`interface_type`·`description`이 입력과 같다. `security_groups` 속성이 `security_group_names`가 가리키는 SG id와 `security_group_ids` 입력값의 합집합이다. `Name` 태그가 `<prefix>-<eni_key>-eni`다 | RSC-ENI-01~06, ARCHITECTURE 7절 | test |
| TST-32 | full | `eni` 대상 경로의 `network_interface_id`가 그 키의 ENI id와 같고 나머지 대상 속성은 `null`이다. 같은 입력의 `network_interface_id` 대상 경로와 공존한다 | RSC-ENI-07, RSC-RT-01, RSC-RT-02 | test |
| TST-33 | basic + ENI 1개 | `eni_interfaces` 항목 1개를 더해도 기존 리소스 변경 0건이고 ENI 1개만 생성된다. 어떤 경로도 그 ENI를 참조하지 않아도 plan 이 실패하지 않는다 | RSC-ENI-01, [7.5절](#75-수명주기-정책) | test + plan |
| TST-34 | full | `security_groups` 항목마다 `aws_security_group` 1개가 그 키로 만들어지고 `name`과 `Name` 태그가 `<prefix>-<sg_key>-sg`, `vpc_id`가 이 VPC다. `ingress`·`egress`는 provider에서 Optional+Computed라 plan에서 미확정 값이므로 인라인 룰 수를 `assert`하지 않는다 | RSC-SG-01, RSC-SG-03, ARCHITECTURE 7절 | test |
| TST-35 | full | `aws_vpc_security_group_ingress_rule`·`egress_rule` 수가 모든 SG의 `ingress`·`egress` 룰 수 합과 같고 키가 `<sg_key>/<direction>/<rule_name>`이다. 각 룰의 `ip_protocol`·포트·소스 필드가 입력과 같고 나머지 소스 필드는 `null`이며 `security_group_id`가 그 키의 SG다 | RSC-SG-03, RSC-SG-04, ARCHITECTURE 6절 | test |
| TST-36 | basic + `security_groups` 1개(룰 없음) | 어떤 ENI도 참조하지 않고 룰도 없는 SG를 더해도 plan이 실패하지 않고 그 SG가 선언된 대로 만들어지며, 두 방향의 룰 리소스가 0개다. `security_group_ids` 출력에 그 키가 있다 | RSC-SG-01, RSC-SG-05 | test |
| TST-37 | eks | `eks.tfvars`로 plan이 성공하고 스택 5개의 서브넷·NACL·DB Subnet Group 수가 입력과 같다. 3 AZ 구성에서 서브넷 키가 `<stack>/<name>` 형식이고 AZ ID가 3종이다 | ARCHITECTURE 13.3절, RSC-AZ-02, ARCHITECTURE 6절 | test |
| TST-38 | full | 네 종류의 Subnet Group이 각각 그 키로 만들어지고 `name`과 `Name` 태그가 `<prefix>-<key>-sng`·`-ecsng`·`-rssng`·`-mdsng`이며, 같은 그룹 이름을 유형이 다르게 써도 plan이 실패하지 않는다. 각 그룹의 `subnet_ids`가 나열한 멤버와 같다 | RSC-SUB-05·09·11·12·13, ARCHITECTURE 7절 | test |
| TST-39 | eks | `flow_logs`에 항목 2개(`cloud-watch-logs`, `s3`)를 선언하면 `aws_flow_log`가 2개이고 키가 두 목적지 키다. `s3` 항목에만 `destination_options`가 있고 `cloud-watch-logs` 항목에는 없으며, `iam_role_arn`은 `cloud-watch-logs` 항목에만 값이 있다. `log_format`이 29개 필드 기본값이고 `flow_log_ids` 출력의 키가 두 항목 키와 같다 | RSC-FLOW-01·03·05·07, ARCHITECTURE 10절 | test |
| TST-40 | basic | `context`가 참조 버전 출력의 부분집합으로 받아들여진다. `name_prefix`·`tags`·`region`·`pri_domain`만 준 객체, 선택 필드를 모두 채운 객체(`cost_center`는 number), 모듈이 쓰지 않는 필드를 섞은 객체 셋 모두 plan 이 성공한다 | ARCHITECTURE 8.1절, 11절 | test |

### 8.6 실패 케이스

실패해야 하는 입력과 그 검사를 `validation`·`precondition` 중 어디에 두는지는 [ARCHITECTURE 9.2.1·9.2.2절](ARCHITECTURE.md#92-검사-배치) 두 표가 정의한다. 이 절은 두 표를 다시 나열하지 않는다.

- 테스트는 ARCHITECTURE 9.2.1·9.2.2절 표의 행마다 그 검사에 걸리는 잘못된 입력을 하나 만들어 plan 실패를 확인한다. `run` 블록 ID는 그 행의 ID를 그대로 쓴 `TST-F-<행 ID>` 형식이다(예: `TST-F-V-01`, `TST-F-P-03`). 근거 요구사항 ID는 한 검사에 여러 행이 대응할 수 있어 ID로 쓰지 않는다.
- 잘못된 입력은 그 검사가 걸리는 가장 작은 기준 입력(대개 basic.tfvars)에 잘못된 값 하나만 더해 만든다. 예를 들어 `enable_ipv6 = false`인 basic.tfvars에 서브넷 `ipv6_index`, `::/0` 경로, `ipv6_cidr_block` 룰 중 하나만 더한 입력은 plan 실패다(RSC-VPC-05, RSC-RT-01, RSC-NACL-05).
- 본문에 실패 조건을 추가하거나 바꾸면 같은 변경에서 [ARCHITECTURE 9.2절](ARCHITECTURE.md#92-검사-배치) 두 표를 갱신한다. 이 절에는 조건을 다시 적지 않는다.

---

## 9. 완료 기준

아키텍처 수준의 완료 기준이다. 경로·리소스 수, 이름·태그 일치, 실패 조건 같은 리소스 수준 기준은 [8.5절](#85-검증-항목)이 `terraform test` 항목으로 정의한다.

- 변수 추가만으로 신규 Stack을 Multi-AZ 형태로 생성할 수 있어야 하며, 신규 Workload가 증가하더라도 Terraform 모듈 코드 변경 없이 선언형 입력만으로 수평 확장할 수 있어야 한다.
- 각 Stack은 독립적인 Subnet Set을 가지며, 서브넷마다 가리킬 Route Table을 스택별로 다르게 적을 수 있어야 한다.
- 특정 Stack 제거가 다른 Stack의 Subnet, Shared Network의 Route Table·NAT, Terraform State Address에 영향을 주지 않아야 한다.
- VPC Peering 연계는 [ARCHITECTURE 5.2절](ARCHITECTURE.md#52-vpc-peering)의 조건을 만족해야 한다.

### 9.1 Definition of Done

릴리스 전 다음을 모두 만족해야 한다.

- [ ] REQUIREMENTS·ARCHITECTURE 두 문서와 구현이 일치한다
- [ ] 이름 규칙([ARCHITECTURE 7절](ARCHITECTURE.md#7-이름-규칙))이 모든 리소스에 적용되었다
- [ ] 태그 병합 순서와 보호 키([7.3절](#73-태그-정책))가 적용되었다
- [ ] 보안 기본값([7.4절](#74-security-by-default))이 입력으로 꺼지지 않는다
- [ ] 검사 표의 모든 행([ARCHITECTURE 9.2절](ARCHITECTURE.md#92-검사-배치))이 구현되고 실패 테스트를 통과한다
- [ ] 출력 표([ARCHITECTURE 10절](ARCHITECTURE.md#10-출력-계약))의 항목이 모두 존재한다
- [ ] `terraform fmt -check` 통과
- [ ] `terraform validate` 통과(모듈 `required_version` 하한 버전에서)
- [ ] `terraform test` 전 항목 통과
- [ ] 기준 입력 5종의 `plan` 이 의도한 리소스만 만든다
- [ ] README 의 Input Variables·Outputs 표가 갱신되었다
- [ ] Breaking Change 여부를 검토하고 버전을 정했다([7.7절](#77-버전과-호환성))
- [ ] 새로 내린 결정을 [10절](#10-결정-기록)에 기록했다

---

## 10. 결정 기록

이 모듈에서 확정한 설계 결정을 ADR(Architecture Decision Record) 형식으로 모아 둔다. 요구사항 본문은 결정 결과만 담고, 결정의 일자·배경·대체안·철회 이력은 이 절에만 남긴다.

- 기록 규칙: 결정 하나에 행 하나를 두고 번호는 `DEC-<번호>`로 이어 붙인다. 기존 행은 고치지 않고 번복·보완은 새 행으로 추가한다. 요구사항 ID 를 삭제하면 그 사실도 행으로 남긴다.
- 예외: `상태`·`대체` 두 열은 후속 결정을 반영할 때 갱신한다(DEC-084). 결정을 추가하는 사람은 그 결정이 내용을 바꾼 이전 행의 두 열을 **같은 변경에서** 갱신한다. 기준은 **결정의 내용이 바뀐 경우**다. 후속 결정이 그 값·구조·범위를 바꾸면 채우고, 일부만 바뀌었으면 `부분 대체`·`부분 번복`·`부분 정정`으로 적는다. 문서 구조나 문구만 정리한 결정(DEC-079 등)은 대체로 보지 않는다. 나머지 열은 고치지 않는다.
- 반영 위치의 절 번호와 요구사항 ID 는 결정 시점 기준이다. 이후 문서 정리로 삭제되거나 옮겨진 항목은 뒤에 추가된 행이 설명한다. 특히 DEC-100 이전 행의 `REQ-100`~`REQ-103` 절 번호는 재구성 전 문서 기준이며, 현재 좌표는 DEC-100 의 매핑 표로 찾는다. DEC-100~DEC-102 행의 `POLICIES`·`ARCHITECTURE`·`REQ-101`~`REQ-102` 절 번호는 5문서 체제(DEC-100~DEC-102 시점) 기준이며, 현재 좌표는 DEC-103 의 매핑 표로 찾는다. 요구사항 ID(`RSC-*`, `V-*`, `P-*`, `TST-*`)는 두 재구성 모두에서 바뀌지 않았다.
- 일부 행의 `반영 위치`와 근거에 `docs/…`, `old/…`, `requirements/*.tfvars`, `tests/…`, `POLICIES.md`, `DECISIONS.md` 경로가 남아 있다. 앞의 둘은 재구현 기간의 작업 문서와 이전 구현 보존본이라 삭제했고(DEC-098), `requirements/*.tfvars`·`tests/…`는 저장소에 두지 않는 로컬 검증 자산이며(DEC-099), `POLICIES.md`·`DECISIONS.md`는 이 통합(DEC-103)으로 REQUIREMENTS·ARCHITECTURE 두 문서에 흡수되어 삭제되었다. 그 경로는 결정 시점의 기록이며 현재 트리에 없거나 git 추적 대상이 아니다.

| 번호 | 일자 | 상태 | 대체 | 항목 | 결정 | 반영 위치 |
| --- | --- | --- | --- | --- | --- | --- |
| DEC-001 | 2026-09-10 | 유효 | — | `context` 입력 | **필수**. tfmodule-context `v1.3.5` 출력을 받아 리소스 이름 접두어(`name_prefix`), 태그 병합 1단계(`tags`), 리전(`region`)의 공급원으로 쓴다. `vpc_name`, `region`, `peer_region` 입력을 두지 않는다 | 2.2, 2.3, 4절, RSC-DNS-01 |
| DEC-002 | 2026-09-10 | 번복됨 | DEC-068 | Subnet Role | **4종 고정**. `public`, `private`, `database`, `intra`(REQ-101 3.1절). 파생 Role을 두지 않는다 | 3.4, RSC-SUB-02 |
| DEC-003 | 2026-09-10 | 유효 | — | 기본 SG·RT·NACL | **항상 채택**. 채택 여부·룰 입력을 두지 않는다. 기본 SG 인바운드·아웃바운드 전면 차단은 조직 보안 기준선으로 확정한 것이다 | 3.8, RSC-DEF-01 |
| DEC-004 | 2026-09-10 | 유효 | — | IPv6 | **선택 지원**. `enable_ipv6` 기본 `false` | RSC-VPC-05, RSC-PUB-06, RSC-RT-05 |
| DEC-005 | 2026-09-10 | 부분 대체 | DEC-044 | Shared Private Subnet | **Interface Endpoint ENI 전용**. Toolchain·Observability는 `stack_subnets`의 스택으로 정의한다 | RSC-PUB-07, RSC-VPCE-03 |
| DEC-006 | 2026-09-10 | 유효 | — | DNS 속성·테넌시 | **고정**. DNS 지원·호스트 이름 항상 활성, 테넌시 `default`. 입력을 두지 않는다 | RSC-VPC-04 |
| DEC-007 | 2026-09-11 | 번복됨 | DEC-063 | Route Table·NAT 모델 | **명시 선언으로 전환**. NAT·RT 모드와 호환표를 제거하고 `route_tables`를 입력으로 선언한다. 서브넷 AZ 그룹은 `route_table` 키를 참조한다. 스택 `internet_egress` 플래그는 제거한다 | REQ-101 4·5절, 3.5, 3.6, 4절 |
| DEC-008 | 2026-09-11 | 번복됨 | DEC-068 | `database` 인터넷 경로 | **옵션**. 기본은 `none`이며 OS 패치 등 외부 인터넷 리소스 접근이 필요하면 `nat` RT를 참조한다. `intra`는 `none` 고정 | REQ-101 3.1절, 3.4, RSC-SUB-04 |
| DEC-009 | 2026-09-11 | 유효 | — | 리소스 이름 규칙 | **호출자 키 기반**. 서브넷·RT는 호출자가 정한 이름을 키로 하고 `Name`은 `<prefix>-<키>-<유형 접미어>`다. 모듈이 스택·Role·AZ를 조합해 이름을 만들지 않는다 | REQ-101 9.1절, 2.1, 2.2 |
| DEC-010 | 2026-09-11 | 번복됨 | DEC-067 | 서브넷 AZ 그룹 | **Role 안에서 AZ로 묶어 선언**. 그룹이 `route_table`을 한 번 적고 서브넷은 `이름 = CIDR`로 나열한다. 한 그룹에 서브넷 여러 개를 둘 수 있다. AZ는 AZ ID로 받는다 | REQ-101 3.1절, 2.4, 3.3, RSC-SUB-01, 4절 |
| DEC-011 | 2026-09-11 | 번복됨 | DEC-063·064 | NAT 선언 위치 | **Route Table에 통합**. `nat` RT가 `nat_public_subnet`을 선언하면 그 RT 키로 NAT를 만든다. 별도 `nat_gateways` 입력을 두지 않고 NAT 공유 구성은 지원하지 않는다 | REQ-101 4절, 3.5, RSC-RT-01 |
| DEC-012 | 2026-09-11 | 부분 대체 | DEC-068·094 | DB Subnet Group | **스택 필드 `db_subnet_groups`로 멤버까지 선언**. 그룹 이름이 리소스 키이고 이름은 `<prefix>-<db_subnet_group>-sng`, 값은 넣을 서브넷 이름 집합이다. 스택당 여러 그룹을 둘 수 있고 나열하지 않은 `database` 서브넷은 그룹에 들어가지 않는다. `create_db_subnet_group` 불리언과 단일 문자열 안을 대체한다 | 2.1, 2.2, RSC-SUB-05, 3.14, 4절 |
| DEC-013 | 2026-09-11 | 부분 대체 | DEC-040·063 | Public IGW Route Table | **호출자가 선언**. 자동 생성·예약 키·필드 생략 같은 예외를 두지 않는다. 모든 RT는 `route_tables`에 선언하고 모든 AZ 그룹은 `route_table`을 적는다. NAT 위치는 `nat_public_subnet`으로 직접 지정한다. 입력과 리소스의 1:1 대응, 그룹 구조 일관성, 도출 로직 배제를 위해 자동 생성 안(2026-09-11 오전)을 철회한 결정이다 | REQ-101 5절, RSC-PUB-04, RSC-RT-01, RSC-RT-03 |
| DEC-014 | 2026-09-11 | 부분 대체 | DEC-068 | 스택 NACL | **스택당 1개**. `stack_subnets.<stack>.nacl` 하나가 그 스택의 모든 Role 서브넷에 연결된다. Role별 NACL(`nacl.<role>`)은 두지 않으며 NACL 키와 이름은 스택 키만 쓴다 | 2.1, 2.2, RSC-NACL-01, 4절 |
| DEC-015 | 2026-09-11 | 번복됨 | DEC-032 | `SubnetRole` 태그 | **제거**. 모듈이 참조하거나 검증하는 곳이 없어 리소스 범위 태그는 `Stack`, `ResourceScope` 2개만 둔다 | REQ-101 8.1·8.2절, 5절 |
| DEC-016 | 2026-09-11 | 번복됨 | DEC-081 | VGW `propagate_to` | **키 나열만 허용**. `["*"]` 와일드카드를 제거해 2.4절 참조 검사에 예외를 두지 않는다 | RSC-VPN-01, RSC-VPN-03 |
| DEC-017 | 2026-09-11 | 유효 | — | Gateway Endpoint 연결 | **association 리소스**. `aws_route`가 아니라 `aws_vpc_endpoint_route_table_association`으로 연결하고 키는 `<service>/<rt_key>` | 2.1, RSC-RT-06 |
| DEC-018 | 2026-09-11 | 유효 | — | `context.region` 용도 | **Interface Endpoint 서비스 이름**. 리소스 배치 리전은 호출자 provider가 정한다. Peering 대상 리전 용도는 2026-09-14 Peering 제외로 삭제 | REQ-101 9.1절, RSC-VPCE-02 |
| DEC-019 | 2026-09-11 | 부분 대체 | DEC-067 | IPv6 인덱스 미지정 | **미할당**. `ipv6_indexes`에 없는 서브넷은 IPv6 CIDR을 갖지 않고 인덱스 중복은 plan 실패 | RSC-VPC-05, 5절 |
| DEC-020 | 2026-09-11 | 부분 대체 | DEC-092 | Flow Log 생성 리소스 이름 | **`<prefix>-vpc-flow-lg`, `<prefix>-vpc-flow-role`**. 태그는 `resource_tags.flow_log`를 공유한다 | 2.2, 2.3, RSC-FLOW-03 |
| DEC-021 | 2026-09-11 | 부분 대체 | DEC-054·070 | 스택 `type`·자동 태그 | **제거**. 스택 성격 입력 `type`과 그로부터 만들던 `ServiceRole` 태그, EKS 자동 태그를 두지 않는다. 성격·컨트롤러 태그는 호출자가 AZ 그룹 `tags`에 직접 정의한다 | REQ-101 3.1·8절, 2.3, 4절, REQ-103 |
| DEC-022 | 2026-09-14 | 유효 | — | 문서 우선순위 | **주제별 정의 문서 표로 전환**. "충돌 시 REQ-101 우선" 같은 문서 단위 우선순위를 없애고 REQ-101 1.1절 표의 정의 문서를 따른다 | REQ-101 1.1·9.1절, 1절, REQ-103 1절 |
| DEC-023 | 2026-09-14 | 유효 | — | 스택 전용 NAT·RT | **제거**. NAT와 Route Table은 항상 Shared Network 리소스다. `route_tables.<key>.stack` 필드, `stacks.<stack>.route_table_ids`·`nat_gateway_ids` 출력, `stack` RT 참조 제한을 삭제한다. 스택 전용 Public Subnet에는 NAT를 두지 않는다 | REQ-101 3·3.1·4·5·8.2절, 2.3, 2.4, RSC-SUB-04·07, RSC-NAT-02·04, RSC-RT-01·10, 3.14, 4절 |
| DEC-024 | 2026-09-14 | 유효 | — | Flow Log S3 옵션 | **기본값 `null`**. `file_format`, `hive_compatible_partitions`, `per_hour_partition`은 `cloud-watch-logs` 대상에서 값이 있으면 plan 실패. 옵션 무시 동작을 없앤다 | RSC-FLOW-05, 5절 |
| DEC-025 | 2026-09-14 | 부분 대체 | DEC-067 | `azs` 입력 | **제거**. AZ는 AZ 그룹 키(AZ ID)로만 선언하고, VPC 전체에서 서로 다른 AZ ID가 2개 미만이면 plan 실패. `azs` 출력도 삭제한다 | REQ-101 3·9.2절, 3.2, RSC-SUB-03, 3.14, 4절, 5절 |
| DEC-026 | 2026-09-14 | 유효 | — | VPC Peering | **모듈 범위 밖**. tfmodule-aws-vpc-peer로 구성한다. `peer_vpcs` 입력, Peering 리소스·경로·출력, `resource_tags.peering`을 삭제하고, 외부 경로 추가에 견디도록 `aws_route_table` 인라인 `route` 블록을 금지한다 | REQ-101 5·7.1·9.1·10절, 1절, 2.1~2.5, 3.10, RSC-RT-02·07, 3.14, 4절 |
| DEC-027 | 2026-09-14 | 유효 | — | `aws_route` timeouts | **예외로 유지**. 구현 세부이지만 apply 실패 예방을 위해 RSC-RT-08로 기술한다 | 1절, RSC-RT-08 |
| DEC-028 | 2026-09-14 | 부분 대체 | DEC-079 | 실패 조건 목록 | **ID 참조 표로 전환**. "전체" 주장을 없애고 본문 요구사항 ID를 근거로 나열한다. 본문에 실패 조건을 추가하면 같은 변경에서 표를 갱신한다 | 5절 |
| DEC-029 | 2026-09-14 | 부분 정정 | DEC-077 | 문서 중복 정리 | **정의는 한 곳, 나머지는 참조**. 키 체계(2.1), AZ 그룹 구조(3.3), 태그 범위(2.3), `resource_tags` 필드(4절), 수명주기·재생성(2.5), 스택 성격 입력 금지(REQ-101 3.1), 완료 기준(아키텍처 REQ-101 10절, 리소스·테스트 5절)을 단일 정의로 하고 중복 서술을 삭제한다. 삭제한 ID: RSC-SUB-06·07·08, RSC-NAT-04, RSC-RT-10, RSC-NACL-04, RSC-VPCE-05·06. REQ-101 4·5절은 원칙만 남기고 REQ-103 5·6절은 삭제 | REQ-101 3·3.1·4·5·8.2·10절, 1절, 2.3, 2.5, 3.1~3.9, 4절, 5절, REQ-103 |
| DEC-030 | 2026-09-14 | 번복됨 | DEC-042·046·055 | 인터넷 게이트웨이 생성 조건 | **Public Subnet 존재 기준으로 통일**. IGW와 Egress-only IGW를 RT 종류로 구분하지 않고 Public Subnet이 있으면 각 1개 만든다. `default_route`에 `eigw`(IPv6 전용 아웃바운드)를 추가하고 필드를 선택으로 바꿔 기본값을 `igw`로 한다 | REQ-101 3.1·5절, RSC-PUB-05·06, RSC-RT-01·02·05, 4절 |
| DEC-031 | 2026-09-14 | 유효 | — | 범위 밖 서술 정리 | **요구사항 문서는 모듈 요구사항만 담는다**. Shared Service 접근 정책 표는 REQ-101 부록 A(호출자 참고)로 옮기고 6절은 정의·구현 범위만 남긴다. 비용 배부(CUR/Athena) 운영 안내, `context` 필수 변수의 Terraform 기본 동작 서술, 입력 반영 출력 `name_prefix`를 삭제한다. 결정표는 이 문서(`DECISIONS.md`)로 분리한다 | REQ-101 4·6·8.2·10절·부록 A, REQ-102 6절·RSC-OUT-01·3.14 |
| DEC-032 | 2026-09-14 | 부분 대체 | DEC-037 | 리소스 범위 태그 | **제거**. 모듈이 만들던 `Stack`, `ResourceScope` 태그와 보호 키 지정을 삭제하고 보호 키는 `Name`, `ManagedBy` 2개만 둔다. 스택 단위 비용 구분은 호출자가 스택 `tags`에 정의한다. DEC-015의 "2개만 둔다"를 대체한다 | REQ-101 1.1·4·8.1·8.2·10절, 2.3, 5절 |
| DEC-033 | 2026-09-14 | 부분 대체 | DEC-068·083·094 | ElastiCache Subnet Group | **`db_subnet_groups`와 같은 패턴으로 추가**. 스택 필드 `elasticache_subnet_groups = map(set(string))`(기본 `{}`), 리소스 `aws_elasticache_subnet_group`, 키 `<elasticache_subnet_group>`, 이름 `<prefix>-<키>-ecsng`. 멤버는 같은 스택 `database` 서브넷이어야 하고 `db_subnet_groups`와 키가 같아도 허용한다 | 1절, 2.1, 2.2, 2.3, 2.4, 2.5, 3.4, RSC-SUB-09, 3.14, 4절, 5절 |
| DEC-034 | 2026-09-14 | 부분 대체 | DEC-037·051 | `context` 타입 | **v1.3.5 출력의 부분집합**. 모듈이 쓰는 `name_prefix`, `tags`, `region`, `environment`, `cost_center`, `pri_domain`만 필수, `region_alias`·`project`·`env_alias`·`owner`·`team`은 `optional()`. `cost_center`는 `optional(number)`이고 `null`이면 `CostCenter` 태그를 만들지 않는다. "출력 스키마와 동일" 서술을 철회한다 | REQ-101 9.1절, 4절 |
| DEC-035 | 2026-09-14 | 부분 대체 | DEC-038·051 | 기준 입력 예시 | **`requirements/basic.tfvars`를 요구사항 기준 입력으로 확정**. REQ-102 5절 테스트 `variables`의 기준값이며, 주석은 한글로 쓴다(CLAUDE.md 6절 1항 예외). 확장 예시(3 AZ, 전용 Public, NACL, EKS 태그)는 별도 tfvars로 둔다 | REQ-101 1.1절, 5절, CLAUDE.md 3·6절 |
| DEC-036 | 2026-09-14 | 유효 | — | EKS 확장 예시 | **`requirements/eks.tfvars`를 REQ-103 기준 입력으로 확정**. 3 AZ, EKS 스택 5개, Shared Private·Interface Endpoint, 스택 NACL, Flow Log를 담은 확장 예시이며 REQ-103 4절 예시는 이 파일의 `svc` 스택 발췌다. DEC-026 이전의 `peer_vpcs` 블록은 Peering 모듈 호출 안내 주석으로 대체한다. DEC-035의 "별도 tfvars"를 구체화한다 | REQ-101 1.1절, REQ-103 4절, CLAUDE.md 3절 |
| DEC-037 | 2026-09-14 | 번복됨 | DEC-092 | Billing Tag 생성 주체 | **`context.tags`에 위임**. tfmodule-context v1.3.5 가 `CostCenter`, `Team`, `Project`, `Environment`, `Department`, `Owner`, `Customer`, `ManagedBy`(`provisioner` 변수)를 `context.tags`로 이미 내므로 모듈이 `CostCenter`, `Environment`, `ManagedBy`를 다시 만들지 않는다. 모듈 생성 태그는 `Name` 하나, 보호 키도 `Name` 하나다. `context.environment`, `context.cost_center`는 모듈이 쓰지 않으므로 `optional()`로 내린다. DEC-032 의 보호 키 2개와 DEC-034 의 `cost_center` `null` 처리 서술을 대체한다 | REQ-101 8.1·8.2·9.1·10절, 4절 |
| DEC-038 | 2026-09-14 | 유효 | — | 기준 tfvars 의 위치 | **examples 검증 스택 입력으로 확정**. `basic.tfvars`, `eks.tfvars`의 `context`, `team`, `cost_center`는 `module "ctx"` 입력이고 그 외 최상위 키가 이 모듈 입력이다. 5절 첫 검증 항목은 "모듈 대상 키"로 한정하고, `assert`가 변수 타입을 볼 수 없으므로 필드별 대응 리소스 존재로 검증한다. DEC-035 의 "테스트 variables 기준값"을 구체화한다 | REQ-101 1.1절, 5절, basic.tfvars, eks.tfvars |
| DEC-039 | 2026-09-14 | 번복됨 | DEC-068 | Role 키 검증 | **4종 외 Role 키는 plan 실패**. `stack_subnets.<stack>.subnets`의 1단계 키가 `public`·`private`·`database`·`intra` 가 아니면(오타 포함) validation 으로 실패시킨다. 오타 그룹이 어떤 Role 검사에도 걸리지 않고 서브넷을 만드는 틈을 막는다 | REQ-101 3.1절, RSC-SUB-01, 4절, 5절 |
| DEC-040 | 2026-09-14 | 유효 | — | 미참조 Route Table | **허용으로 전환**. 어떤 AZ 그룹도 참조하지 않는 RT를 plan 실패로 알리던 RSC-RT-03 을 "선언된 대로 만들고 실패·경고 없음"으로 바꾼다. 스택 제거가 그 스택만 쓰던 RT·NAT 삭제를 강제해 2.5절·REQ-101 10절의 "스택 제거는 Shared RT·NAT 에 영향 없음"과 충돌했고, RT 선행 선언 후 스택 추가라는 2단계 작업도 막았기 때문이다. 5절 실패 표의 해당 행을 삭제하고 미참조 RT 추가 테스트를 넣는다 | 2.5, RSC-RT-03, 5절 |
| DEC-041 | 2026-09-14 | 부분 번복 | DEC-047 | Flow Log CloudWatch 전용 옵션 | **기본값 `null`, 대상 불일치는 plan 실패**. `retention_in_days`·`kms_key_id` 기본값을 `null`로 바꾸고 `create_log_group = true`가 아닐 때 값이 있으면 실패시킨다. `retention_in_days`가 `null`이면 `90` 적용. RSC-FLOW-02 의 "`create_log_group`을 주면"을 `bool` 에 맞게 "`true`이면"으로, "미지정" 실패를 본문에 명시한다. DEC-024 의 S3 전용 옵션 원칙을 CloudWatch 전용 옵션에도 대칭 적용한 결정이다 | RSC-FLOW-02, RSC-FLOW-03, 5절, eks.tfvars |
| DEC-042 | 2026-09-14 | 번복됨 | DEC-063 | `default_route` 필수 | **기본값 제거**. `route_tables.<key>.default_route`를 필수로 두고 생략하면 plan 실패. DEC-030 의 "선택 필드, 기본 `igw`"를 번복한다. REQ-101 5절 "입력 파일만 읽어도 어느 서브넷이 어느 경로를 갖는지 드러나야 한다"와 기본값이 상충하고, `iso = {}` 같은 빈 객체가 조용히 IGW RT 가 되는 것을 막기 위함이다 | REQ-101 5절, RSC-RT-01, 4절, 5절, basic.tfvars, eks.tfvars |
| DEC-043 | 2026-09-14 | 부분 대체 | DEC-092 | `common_billing_tags` 입력 | **삭제, `tags`로 통합**. 두 입력이 타입(`map(string)`)·적용 범위(모든 리소스)가 같고 병합 순서만 달라 같은 키를 두 곳에 적을 수 있었다. 조직 추가 Billing 키(`Platform` 등)는 모듈 공통 `tags`에 둔다. 8.1절 3단계 순서에서 `common_billing_tags`를 제거한다 | REQ-101 8.1·8.2·9.2·10절, 4절, 5절, basic.tfvars, eks.tfvars |
| DEC-044 | 2026-09-14 | 부분 대체 | DEC-092 | `shared_private_subnets` 이름 | **`vpc_endpoint_subnets`로 개명**. 용도가 Interface Endpoint ENI 전용(DEC-005)인데 이름이 범용 Shared Private 을 암시해 Toolchain 등을 여기 두려는 오해를 불렀다. 구현 전이라 비용이 없다. 리소스 키 `shared-network/private/<name>` → `shared-network/vpce/<name>`, 출력 `shared_network.private_subnet_*` → `shared_network.vpce_subnet_*`, `resource_tags.shared_private_subnet` → `resource_tags.vpc_endpoint_subnet` 도 함께 바꾼다 | REQ-101 3.1·5·9.2절, 2.1, RSC-AZ-02, 3.3, RSC-PUB-07, RSC-NACL-01, RSC-VPCE-03, RSC-OUT-03, 3.14, 4절, 5절, REQ-103 4절, eks.tfvars |
| DEC-045 | 2026-09-14 | 부분 대체 | DEC-092 | 태그 병합 순서 | **`merge(context.tags, resource_tags.<유형>, 사용자 커스텀 tags, { Name })`로 확정**. 1단계 `context.tags`(필수), 2단계 `resource_tags`(선택, 기본 `{}`), 3단계 사용자 커스텀 `tags`(모듈 공통 → 스택 → AZ 그룹 → 인스턴스, 각 선택·기본 `{}`) 순이며 `Name`은 마지막에 붙인다. 리포트 I-04 의 순서 반전 제안은 채택하지 않는다 | REQ-101 8.1절, 2.3, 4절, 5절 |
| DEC-046 | 2026-09-14 | 부분 대체 | DEC-066 | Egress-only IGW 위치 | **`nat` Route Table에 통합**. `enable_ipv6 = true`이면 `nat` RT가 IPv4 기본 경로(NAT)와 IPv6 기본 경로(Egress-only IGW)를 함께 갖고, Egress-only IGW는 `nat` RT가 1개 이상일 때 1개 만든다. `default_route` 값 `eigw`와 RSC-PUB-06(Public Subnet 없는 `eigw`·`nat` RT 실패)을 삭제한다. DEC-030 의 `eigw` 추가와 "Public Subnet 존재 기준" 중 Egress-only IGW 부분을 번복한다 | REQ-101 3.1·4·5절, RSC-PUB-05, RSC-RT-01·02·05, 4절, 5절, 세 tfvars |
| DEC-047 | 2026-09-14 | 유효 | — | 파생 기본값 원칙 | **정적 기본값은 타입에, 파생 기본값은 `null`로 받아 본문·description에 명시**. 파생 원본이 `null`이면 plan 실패(예: `domain_name` 생략 + `context.pri_domain` `null`). RSC-FLOW-03 의 "`retention_in_days` `null`이면 `90`"은 코드 안 상수가 되므로 철회하고 `null` = CloudWatch 기본(보존 무제한)으로 한다. DEC-041 의 `90` 적용을 번복한다 | 2.4, RSC-DEF-04, RSC-DNS-01, RSC-FLOW-03, 4절, 5절 |
| DEC-048 | 2026-09-14 | 유효 | — | VPC Peering 절 삭제 | **REQ-102 3.10절과 RSC-PCX-01~03, RSC-RT-07 삭제**. 범위 밖 항목이 요구사항 ID를 갖던 모순을 없앤다. 내용은 REQ-101 7.1절(정의), RSC-RT-02(인라인 `route` 금지), 3.13절 `route_table_ids` 행이 이미 담는다. DEC-026 반영 위치의 "3.10"은 삭제로 확정한다. 이후 절 번호는 3.10 VPN, 3.11 Flow Logs, 3.12 Private DNS, 3.13 출력으로 당긴다 | REQ-101 1.1·7.1·7.2절, 1절, 3.10~3.13, 4절, eks.tfvars |
| DEC-049 | 2026-09-14 | 유효 | — | 문서 구조·중복 정리 | **정의는 한 곳, 배경은 DECISIONS**. (1) 2.6절 "서브넷 AZ 그룹 구조" 신설, AZ ID 채택 규칙을 2.4에서 이동. (2) `vpc_endpoint_subnets`를 3.3에서 3.9로 옮기고 RSC-PUB-07 → RSC-VPCE-07. (3) 삭제 ID: RSC-SUB-03(3.4 도입 문장으로), RSC-DNS-03(AWS 사실), RSC-DEF-05(1절 제외 목록으로), RSC-OUT-02·03·05(출력 표로), RSC-PUB-06, RSC-PUB-07(이동), RSC-RT-07. (4) REQ-101 9.2절·부록 A·10절 재서술 항목·3절 AZ 장애 항목·1절 목표 7항 삭제, 부록 A는 `docs/shared-service-access-policy.md`로 이동. (5) REQ-102 6·7절을 1절에 통합, REQ-102·103 HTML 주석 삭제. (6) 본문의 결정 배경 문장 삭제. (7) 이전 설계 잔재인 REQ-101 3.1절 "Role별 경로 정책은 Role 이름을 키로" 문장을 현재 모델로 교체. (8) REQ-101 9절을 `context` 단일 절로 정리(9.1 → 9) | REQ-101 전체, REQ-102 전체, REQ-103 1·2절 |
| DEC-050 | 2026-09-14 | 번복됨 | DEC-057 | 예약 스택 키 | **`shared-network` 예약**. 스택 키가 `shared-network`이면 서브넷 키가 Shared Public 키 접두어와 겹치므로 plan 실패. Shared Public NACL 이름은 `<prefix>-public-nacl`에서 `<prefix>-shared-public-nacl`로 바꿔 스택 키 `public`과의 이름 충돌을 없앤다 | 2.2, 5절 |
| DEC-051 | 2026-09-14 | 부분 대체 | DEC-059·062·069 | 기능별 검증 입력 | **`requirements/full.tfvars` 추가**. basic.tfvars 에 없는 스택 전용 Public, `intra`, IPv6, 보조 CIDR, EIP 재사용, `public_subnets_nacl`, VGW·CGW, DHCP, S3 Flow Log 를 2 AZ 로 담는다. 5절 기능별 `run`은 이 파일 또는 basic.tfvars + 기능 입력을 기준값으로 한다. DEC-035 가 말한 "전용 Public" 예시는 eks.tfvars 가 아니라 이 파일에 둔다 | REQ-101 1.1절, 5절, full.tfvars, CLAUDE.md 3·6절 |
| DEC-052 | 2026-09-14 | 부분 대체 | DEC-083·089·092 | 서브넷·NACL 필드 세부 | **`map_public_ip_on_launch` `false` 고정(입력 없음)**, IPv6 CIDR 이 있는 서브넷은 `assign_ipv6_address_on_creation = true`. NACL `ingress`·`egress`는 각 선택(기본 `{}`)이고 비어 있으면 AWS 기본 동작(전체 거부). 스택 전용 Public Subnet 에는 `resource_tags.stack_subnet` 적용 | RSC-PUB-01·03, RSC-VPC-05, RSC-NACL-02, 2.3, 4절 |
| DEC-053 | 2026-09-14 | 부분 대체 | DEC-083 | `subnet_*` 출력 범위 | **Shared Public·VPC Endpoint 서브넷 포함**. `route_table_association_ids`와 범위를 맞추고 키 접두어로 구분한다. `shared_network`·`stacks` 객체는 편의 출력으로 유지 | RSC-OUT-01, 3.13 |
| DEC-054 | 2026-09-14 | 유효 | — | 기록 정리 | (1) DEC-018 은 2026-09-14 에 기존 행을 직접 수정한 규칙 위반이며 수정 전 문구는 복원하지 않는다. 이후 변경은 새 행으로만 한다. (2) DEC-040 은 DEC-013 반영 위치의 RSC-RT-03 항목을 대체한다. (3) DEC-021 의 "AZ 그룹 `tags`에 직접 정의"는 REQ-101 3.1절·REQ-103 3절대로 "스택 `tags` 또는 AZ 그룹 `tags`"로 보완한다(`ClusterName` 은 스택 `tags`). (4) DEC-035 의 "전용 Public" 예시는 DEC-051 이 full.tfvars 로 이행한다 | DECISIONS.md |
| DEC-055 | 2026-09-14 | 부분 대체 | DEC-066 | IGW 생성 조건 | **`igw` Route Table 존재 기준으로 전환**. IGW는 `default_route = "igw"`인 RT가 1개 이상일 때 1개 만든다. Public Subnet은 RSC-PUB-04로 `igw` RT를 반드시 참조하므로 기존 조건(Public Subnet 존재)을 포함하고, Egress-only IGW(DEC-046)와 같은 RT 기준이 된다. Public Subnet 없이 `igw` RT만 선언한 입력에서 `0.0.0.0/0` 경로의 대상이 없어지는 빈틈을 막는다. IGW·Egress-only IGW는 RT 종류에서 파생되는 단일 리소스이므로 그 종류의 RT를 처음 추가·마지막 제거할 때 생성·삭제되는 것을 2.5절 "다른 키 변경 0건" 규칙의 예외로 명시한다. DEC-030 의 "Public Subnet 존재 기준" 중 IGW 부분을 번복한다 | RSC-PUB-05, 2.5, 5절 |
| DEC-056 | 2026-09-14 | 부분 대체 | DEC-067 | `ipv6_indexes` 검증 | **`enable_ipv6 = false`인데 `ipv6_indexes`가 비어 있지 않은 AZ 그룹이 있으면 plan 실패**. 인덱스 허용 범위는 `0`~`255`(/56 안의 /64)이며 범위 밖도 plan 실패. 대상에 적용되지 않는 옵션을 조용히 무시하지 않는 원칙(DEC-024·041·047)을 IPv6 옵션에도 적용한다 | RSC-VPC-05, 2.6, 4절, 5절 |
| DEC-057 | 2026-09-14 | 유효 | — | 예약 스택 키 | **`shared-` 접두어 전체 예약**. 스택 키가 `shared-`로 시작하면 plan 실패. DEC-050 의 `shared-network` 단일 예약어는 Shared Public NACL 이름 `<prefix>-shared-public-nacl`과 스택 키 `shared-public`의 이름 충돌을 남겼다. Shared 리소스의 키 접두어와 이름은 모두 `shared-`를 쓴다 | 2.2, 5절 |
| DEC-058 | 2026-09-14 | 부분 대체 | DEC-081·083·089 | 누락 보강 | (1) NACL 룰 필드 제약: `rule_number` `1`~`32766`, `cidr_block`·`ipv6_cidr_block` 중 정확히 하나, `tcp`·`udp`는 `from_port`·`to_port` 필수, `icmp`·`icmpv6`는 `icmp_type`·`icmp_code` 필수. 위반 시 plan 실패. (2) Endpoint SG는 `security_group_ids`가 `null`인 Interface Endpoint가 1개 이상일 때만 1개 만들어 그 Endpoint들에 붙이고, 없으면 `vpc_endpoint_security_group_id`는 `null`. (3) VGW `existing_id` 사용 시 `aws_vpn_gateway_attachment`(단일 키, 태그 없음)로 연결하고 `propagate_to`는 신규·기존 두 경우 모두 허용. (4) 5절에 full.tfvars 기준 검증 항목 5개(EIP 재사용, 스택 전용 Public 태그·`map_public_ip_on_launch`, `intra` 보조 CIDR, S3 Flow Log 로그 그룹·롤 0개, VGW 전파 수) 추가 | 2.1, 2.2, RSC-NACL-02, RSC-VPCE-04, RSC-VPN-02, 4절, 5절 |
| DEC-059 | 2026-09-14 | 유효 | — | 3차 리포트 문구·중복 정리 | (1) DEC-051 의 full.tfvars 기능 목록에 스택 NACL, Interface Endpoint(`sts`, `ssm`), `resource_tags`를 보완한다. (2) full.tfvars Public NACL ingress에 VPC·보조 CIDR 허용(90·91)을, `web` 스택 NACL ingress에 인터넷 443 허용(90)을 추가해 NAT 아웃바운드와 스택 전용 Public LB 유입이 동작하는 예시로 고친다. eks.tfvars 주석의 DEC-014 참조를 RSC-NACL-01 로 바꾼다. (3) REQ-101 3.1절 `database` 행 "기본"을 "권장"으로, 4·8.2·10절의 중복 서술을 참조로 줄이고 9절의 `context` 출력 전용 필드 열거를 삭제한다. RSC-VPC-03 은 구현 방식(`depends_on`) 대신 동작으로 서술한다. (4) CLAUDE.md 5절 태그 항목을 REQ-101 8.1절 순서·보호 키 `Name`과 맞춘다 | REQ-101 1.1·3.1·4·8.2·9·10절, RSC-VPC-03, 2.5, 5절, full.tfvars, eks.tfvars, CLAUDE.md 3·5절 |
| DEC-060 | 2026-09-14 | 부분 번복 | DEC-061 | NACL IPv6 룰 | **호출자가 `ipv6_cidr_block` 룰을 IPv4 룰에 대응해 정의**. NACL은 IPv4·IPv6 룰이 분리되고 미해당 트래픽은 거부되므로, `enable_ipv6 = true`이면 IPv6 CIDR을 가진 서브넷의 전용 NACL에 IPv6 룰이 없으면 IPv6 트래픽이 전부 막힌다. 모듈이 IPv4 룰을 IPv6로 복제하는 안은 입력과 리소스의 1:1 대응 원칙에 어긋나 채택하지 않는다. VPC IPv6 CIDR은 Amazon 할당이라 룰에 적을 수 없어 `::/0` 같은 정적 값만 허용하고, `enable_ipv6 = false`인데 `ipv6_cidr_block` 룰이 있으면 plan 실패(DEC-056 과 같은 원칙). full.tfvars 두 NACL에 인터넷 방향 IPv4 룰과 대응하는 `::/0` 룰을 추가한다 | RSC-NACL-05, 4절, 5절, full.tfvars |
| DEC-061 | 2026-09-14 | 유효 | — | NACL IPv6 예약 값 | **`ipv6_cidr_block = "vpc"`를 VPC IPv6 CIDR 로 치환**. VPC IPv6 CIDR 은 Amazon 할당이라 tfvars 에 적을 수 없어 VPC 내부 IPv6 통신을 NACL 로 허용할 방법이 없었다(DEC-060 의 "정적 값만" 제한). 예약 값 `vpc` 하나만 두고 그 외 값은 IPv6 CIDR 형식을 validation 으로 검사한다. `cidr_block` 에는 예약 값을 두지 않는다(`vpc_cidr` 입력으로 알 수 있다). DEC-060 의 "정적 값만 허용"을 번복한다 | RSC-NACL-05·06, 4절, 5절, full_ipv6.tfvars |
| DEC-062 | 2026-09-14 | 유효 | — | IPv6 기준 입력 분리 | **`basic_ipv6.tfvars`, `full_ipv6.tfvars` 추가, full.tfvars 는 IPv4 전용으로 복귀**. IPv6 는 VPC·서브넷·경로·NACL 에 걸쳐 plan 결과를 바꾸므로 IPv4 기준값과 분리해 두어야 "IPv4 파일 대비 차이가 IPv6 관련에 한정"되는지 검증할 수 있다. 각 IPv6 파일은 대응 IPv4 파일에 `enable_ipv6`, `ipv6_indexes`, IPv6 NACL 룰(full_ipv6 만)만 더한 것으로 유지한다. DEC-051 의 full.tfvars 기능 목록에서 IPv6 를 뺀다 | REQ-101 1.1절, 5절, basic_ipv6.tfvars, full_ipv6.tfvars, full.tfvars, CLAUDE.md 3·6절 |
| DEC-063 | 2026-09-15 | 유효 | — | Route Table 모델 | **목적지 → 대상 표로 전환**. RT 는 `routes`(목적지 CIDR 을 키로, 값은 대상 객체), `propagate_vgw`, `tags` 세 필드만 갖는다. `default_route`와 그 값 `igw`·`nat`·`none`, `nat_public_subnet`, `eip_allocation_id` 를 삭제하고 `routes = {}` 가 경로 없는 RT 다. 같은 RT 의 목적지 중복은 Map 키라 문법적으로 불가능해진다. IPv6 기본 경로도 `"::/0"` 줄로 호출자가 적고 모듈이 IPv4 경로에서 도출하지 않는다. DEC-007·011 의 RT·NAT 통합 모델과 DEC-042 의 `default_route` 필수를 번복한다. DEC-042 가 막으려던 "빈 객체가 조용히 IGW RT 가 되는 것" 은 `routes` 에 기본 대상이 없으므로 생기지 않는다 | REQ-101 4·5절, 3.5, 3.6, RSC-RT-01·02·05, RSC-NAT-01·03, RSC-VPN-01, 4절, 5절, 다섯 tfvars |
| DEC-064 | 2026-09-15 | 유효 | — | NAT Gateway 선언 위치 | **`nat_gateways` 최상위 입력으로 분리**. 키가 NAT 키이고 값은 `public_subnet`(필수), `eip_allocation_id`, `tags` 다. 여러 RT 가 한 NAT 를 참조할 수 있어 경로만 다른 RT 를 추가해도 NAT 가 늘지 않는다(RSC-NAT-05 삭제). NAT·EIP 의 키와 이름이 RT 키에서 `nat_gateways` 키로 바뀐다. DEC-011 을 번복한다 | REQ-101 4절, 2.1, 2.2, 3.5, RSC-NAT-01·02·03·05·06, 4절, 5절 |
| DEC-065 | 2026-09-15 | 유효 | — | 경로 대상 범위 | **모듈 소유 대상은 키·이름으로, 호출자 소유 대상은 `*_id` 로**. 경로 객체는 `gateway`(`igw`·`eigw`·`vgw`), `nat_gateway`(`nat_gateways` 키), `network_interface_id`(호출자가 만든 NAT 인스턴스·어플라이언스 ENI) 중 정확히 하나를 갖는다. NAT 인스턴스를 쓰는 VPC 는 `nat_gateways` 를 비우고 경로가 ENI 를 가리킨다. 인스턴스 자체(AMI, 타입, `source_dest_check`, EIP, SG)는 EC2 영역이라 모듈이 만들지 않는다. VPC Peering·Transit Gateway 는 연결을 만드는 전용 모듈이 경로까지 넣으므로 대상으로 두지 않는다(DEC-026 유지) | REQ-101 4·5·7.1절, 3.6, RSC-RT-01·02, 4절, 5절 |
| DEC-066 | 2026-09-15 | 유효 | — | IGW·Egress-only IGW 생성 조건 | **경로 존재 기준으로 전환**. IGW 는 `gateway = "igw"` 경로가 1개 이상일 때, Egress-only IGW 는 `gateway = "eigw"` 경로가 1개 이상일 때 각 1개 만든다. DEC-055 의 "`igw` RT 1개 이상", DEC-046 의 "`nat` RT 1개 이상" 을 새 구조로 옮긴 것이며 뜻은 같다. 파생 단일 리소스의 첫 생성·마지막 삭제가 2.5절 예외인 점도 그대로다 | RSC-PUB-05, RSC-RT-05, 2.5, 5절 |
| DEC-067 | 2026-09-15 | 유효 | — | 서브넷 선언 형식 | **AZ 그룹 제거, 서브넷 평면 Map 으로 전환**. 서브넷은 이름을 키로 하고 값은 `{ az, cidr, route_table, ipv6_index, tags }` 다. 한 줄이 서브넷 하나이며 그 줄에 배치 AZ, CIDR, 연결할 RT 가 모두 있다. `az`·`cidr`·`route_table` 이 `availability_zone_id`·`cidr_block`·Association 의 `route_table_id` 에 그대로 들어가고 값 변환은 없다. AZ 그룹 `ipv6_indexes` Map 은 서브넷 줄의 `ipv6_index` 로, AZ 그룹 `tags` 는 서브넷 줄의 `tags` 로 내려온다. DEC-010 을 번복한다 | REQ-101 3.1·5절, 2.6, 3.3, 3.4, RSC-SUB-01, RSC-PUB-01, RSC-VPCE-07, RSC-VPC-05, RSC-AZ-01·02, 4절, 5절, 다섯 tfvars |
| DEC-068 | 2026-09-15 | 유효 | — | Subnet Role 계층 | **제거**. `stack_subnets.<stack>.subnets` 는 서브넷 이름 키의 평면 Map 이며 `public`·`private`·`database`·`intra` 계층을 두지 않는다. 서브넷의 성격은 그 줄의 `route_table` 이 가리키는 RT 의 `0.0.0.0/0` 이 정하고, 계층(node, blb, web, app, data)은 서브넷 이름으로 나타낸다. 서브넷 키가 `<stack>/<role>/<name>` 에서 `<stack>/<name>` 으로, 출력 `stacks.<stack>.subnet_ids_by_role` 이 `subnet_ids` 로 바뀐다. 삭제한 ID: RSC-SUB-01(Role 키 4종 검증), RSC-SUB-02(`private` Role 필수), RSC-SUB-04(Role 별 허용 경로). RSC-SUB-05·09 의 멤버 조건은 "같은 스택의 서브넷" 으로 완화하고, RSC-PUB-03 의 스택 전용 Public 은 "`igw` 경로를 가진 RT 를 가리키는 스택 서브넷" 으로 재정의한다. DEC-002·039 를 번복한다. **감수하는 손실**: 의도(Role)와 경로(RT)를 따로 적어 어긋남을 잡던 교차 검사가 없어져 데이터 계층 서브넷이 `igw` RT 를 가리켜도 plan 이 통과한다. DEC-063 으로 RT 가 이미 목적지 → 대상을 명시하므로 Role 을 남기면 같은 정보를 두 번 적게 되고, Role 4종이 운영자의 계층 이름(blb·web·app 이 모두 `private`)과 맞지 않아 계층처럼 오해되는 문제가 더 컸다. 근거는 `docs/tfvars-review.md` 2.2절 | REQ-101 2·3.1·10절, 2.1, 2.3, 2.6, 3.4, RSC-SUB-01·02·04 삭제, RSC-SUB-05·09, RSC-PUB-03, 3.13, 4절, 5절, REQ-103 |
| DEC-069 | 2026-09-15 | 유효 | — | Shared Public 입력 | **`public_subnets` + `public_subnets_nacl` 을 `shared_public` 하나로 통합**. `shared_public = { tags, nacl, subnets }` 로 스택 객체와 같은 모양이 된다. NACL 키 `shared-network/public` 과 이름 `<prefix>-shared-public-nacl` 은 그대로다. `vpc_endpoint_subnets` 는 태그·NACL 필드가 없으므로 객체로 감싸지 않고 서브넷 Map 을 바로 받는다 | 3.3, RSC-PUB-01, RSC-NACL-01, RSC-VPCE-07, 4절, 5절 |
| DEC-070 | 2026-09-15 | 유효 | — | 태그 3단계 구성 | **AZ 그룹 `tags` 를 서브넷 `tags` 로 대체**. REQ-101 8.1절 3단계 안의 순서는 모듈 공통 `tags` → 스택 `tags` → 서브넷 `tags` 이며 RT `tags` 는 그 RT 에만, `nat_gateways.<key>.tags` 는 그 NAT·EIP 에만 적용된다. EKS 컨트롤러 태그(`karpenter.sh/discovery` 등)는 대상 서브넷 줄에 적어 데이터 계층 서브넷에 붙지 않게 한다. 스택 `tags` 로 올리면 Karpenter 가 DB 서브넷에 노드를 띄울 수 있다 | REQ-101 8.1절, 2.3, 4절, 5절, REQ-103 3절 |
| DEC-071 | 2026-09-15 | 부분 정정 | DEC-080 | 검사 위치 | **RT 를 참조하는 검사는 `aws_route_table_association`·`aws_route` 의 `precondition` 에 둔다**. `aws_subnet` 에 `var.route_tables` 를 참조하는 `precondition` 을 두면, 경로가 호출자 ENI(DEC-065)를 가리키는 구성에서 `aws_subnet → var.route_tables → EC2 → aws_subnet` 순환 참조가 생긴다. 대상 택일 검사와 Shared Public·VPC Endpoint 서브넷의 RT 검사(RSC-PUB-04, RSC-VPCE-07)가 대상이다. 첫 apply 에서 ENI ID 가 미확정이면 그 검사는 apply 시점으로 미뤄진다 | 2.4, RSC-PUB-04, RSC-VPCE-07, RSC-RT-01 |
| DEC-072 | 2026-09-15 | 유효 | — | Gateway Endpoint 연결 | **유지**. `vpc_endpoints.gateway` 가 비어 있지 않으면 모든 RT 에 자동 연결한다(RSC-RT-06, DEC-017). RT 마다 `gateway_endpoints` 를 적게 하는 안은 모든 RT 에 같은 값이 반복되고 빠뜨리면 그 RT 의 서브넷이 S3 에 닿지 못하는 것이 apply 뒤에야 드러나 채택하지 않는다 | RSC-RT-06 |
| DEC-073 | 2026-09-15 | 유효 | — | 스택 NACL 기준선 | **요구사항으로 만들지 않는다**. 모든 스택에 같은 골격의 NACL(자기 스택·공용 허용, 다른 스택 거부)을 두는 기준선은 모듈이 강제하지 않고 호출자 예시로만 둔다. 모듈 구현 범위가 스택 NACL 입력까지라는 REQ-101 6절과, 포트 수준 제어는 Security Group 의 책임이라는 원칙을 유지하기 위함이다. 예시는 `docs/shared-service-access-policy.md` 와 `requirements/eks.tfvars` 의 `toolchain` 스택에 둔다 | REQ-101 6절, 3.7 |
| DEC-074 | 2026-09-15 | 유효 | — | 허브 경로 격리 | **전용 RT 채택**. DEC-064 로 NAT 공유가 가능해졌으므로 관측 허브처럼 외부 Peering 경로를 일부 워크로드에만 두어야 하는 스택은 전용 RT 를 선언하고 다른 RT 와 같은 NAT 를 참조한다. NAT 가 늘지 않아 비용 변화가 없다. eks.tfvars 에 `obsv-a1`·`obsv-c1`·`obsv-d1` 로 반영하며 Peering 경로 자체는 여전히 모듈 밖이다(DEC-026) | REQ-101 7.1절, eks.tfvars |
| DEC-075 | 2026-09-15 | 부분 정정 | DEC-079 | 기준 tfvars 재작성 | **다섯 tfvars 를 DEC-063~070 형식으로 재작성**. basic ⊂ full 이 성립하도록 full.tfvars 의 `web` 스택 계층을 basic.tfvars 와 같게 맞추고, CIDR 을 계층별 블록 규칙으로 재배정한다. full.tfvars 에 `network_interface_id` 경로를 가진 RT 를 더해 DEC-065 의 ENI 대상을 검증 대상에 넣는다. 가이드·참조 예시(`docs/demo-101`, `demo-102`, `demo-301`)는 저장소 밖 검증용이며 요구사항 기준 입력이 아니다 | REQ-101 1.1절, 5절, 다섯 tfvars, CLAUDE.md 3절 |
| DEC-076 | 2026-09-15 | 부분 정정 | DEC-080 | 문서 역할 분리 | **모듈 구현 규칙을 `REQ-100-TFMODULE-CODESTYLE.md` 로 분리**. `CLAUDE.md` 는 저장소 운영 규칙(프로젝트 개요, 기술 스택, 디렉터리, 필수 작업 지침, 보안·Git 정책)만 담고, 코드 컨벤션·입력 변수와 출력 구조·Terraform 설계 원칙·검증과 테스트 절차는 REQ-100 이 정의한다. CLAUDE.md 에 있던 tfvars 파일별 설명, `docs/`·`examples/` 구현 안내, 히어독 변수 예시를 제거하고 REQ-100 또는 REQ-101 1.1절 참조로 바꾼다. REQ-100 은 특정 리소스에 종속되지 않으므로 다른 Terraform 모듈 저장소에도 그대로 쓸 수 있다. 문서 계층 표(REQ-101 1.1절)에 REQ-100 행을 더한다 | CLAUDE.md 전체, REQ-100 신설, REQ-101 1.1절, docs/ 참조 |
| DEC-077 | 2026-09-15 | 유효 | — | 재사용된 요구사항 ID | **새 번호로 교체**. DEC-029 가 삭제한 `RSC-RT-10`, DEC-068 이 삭제한 `RSC-SUB-01`, DEC-064 가 삭제로 적은 `RSC-NAT-05` 가 각각 다른 내용으로 본문에 다시 쓰여 1절 "삭제된 ID 는 재사용하지 않는다" 를 어겼다. 현행 요구사항을 `RSC-RT-11`, `RSC-SUB-10`, `RSC-NAT-08` 로 옮기고 세 삭제 ID 는 영구 결번으로 둔다. 3.4절 표는 ID 순서(05·09·10)로 정렬한다. 근거는 `docs/report.md` C-02 | 1절, 3.4, 3.5, 3.6, RSC-VPN-03, 5절, 네 tfvars |
| DEC-078 | 2026-09-15 | 유효 | — | 검사 구현 위치 | **4.1절 두 표로 확정**. 각 검사를 `validation` 과 `precondition` 중 어디에 두는지, `precondition` 이면 어느 리소스에 두는지를 표로 정의한다. 분류 기준은 제약 하나다. `variable` 의 `validation` 은 자기 변수만 참조할 수 있고 다른 변수 참조는 Terraform 1.9 이상 기능인데 이 모듈의 `required_version` 하한은 `1.5.7` 이므로, 두 개 이상의 입력을 함께 보는 검사는 예외 없이 `precondition` 이다. 이에 따라 4절이 `validation` 으로 분류했던 RSC-NACL-05(`enable_ipv6 = false` 인데 `ipv6_cidr_block` 룰)를 `aws_network_acl_rule` 의 `precondition` 으로 옮겨, 같은 문단이 한 검사를 양쪽으로 적던 모순을 없앤다. 분류가 없던 검사(서브넷 이름 전역 유일, CIDR 포함·겹침, AZ 2개 미만, `ipv6_index` 중복, Subnet Group 이름 중복, `rule_number` 중복, 보호 키 등)도 표에 넣고, 입력만 보는 VPC 전역 검사는 단일 리소스 `aws_vpc` 에 모아 한 번만 평가한다. 근거는 `docs/report.md` C-01·G-01 | 2.4, 4.1 신설, 5절 |
| DEC-079 | 2026-09-17 | 유효 | — | 문서 중복·불필요 서술 정리 | **정의는 한 곳, 나머지는 참조**. (1) 문서 계층 표는 REQ-101 1.1절 하나로 두고 REQ-100 1.1절은 자기 행만 남기며, 그 표에 `검사 구현 위치 → REQ-102 4.1` 행을 더한다. (2) 검증 원칙·파생 기본값 원칙·참조 방향 원칙은 REQ-100 3.1·3.2절이 정의하고 REQ-101 5절과 REQ-102 2.4·4절은 참조만 둔다. (3) REQ-102 5절을 5.1 테스트 입력, 5.2 검증 항목 표(`TST-01`~`TST-28`), 5.3 실패 케이스로 재구성하고 실패 조건 표를 삭제한다. 실패 조건의 유일한 정의는 4.1.1·4.1.2 두 표이며 테스트는 그 행마다 `TST-F-<근거 ID>` `run` 을 둔다. 리포트 G-01(실패 조건 표의 RSC-PUB-01 행 누락)은 이 구조 변경으로 해소된다. (4) 본문의 결정 배경을 이 문서 참조로 바꾼다(2.4절 순환 참조 → DEC-071, RSC-NACL-06 → DEC-061). (5) 재서술 축약·삭제: Role 계층 부재(REQ-102 2.6, RSC-SUB-10, RSC-PUB-03), 스택 서브넷 개수(REQ-101 3.1), NAT 키 작명 조언(2.2), 삭제된 `default_route`·`none` 언급(REQ-101 5), 검사되지 않는 IPv6 권장 구성(REQ-101 4), `module "ctx"` 호출 예시(REQ-101 9, README Usage 소관), REQ-103 1~3절. (6) `requirements/eks-arhitecture.png` 를 `eks-architecture.png` 로 개명하고 REQ-103 1절이 목표 아키텍처로 참조한다. 빈 파일 `docs/demo-201-hub-spoke.md` 를 삭제한다. (7) DEC-075 의 "저장소 밖 검증용" 표현을 정정한다. `docs/demo-*` 는 저장소에 남는 참고 예시이며 요구사항 기준 입력이 아니다. 근거는 `docs/report.md` D-01~D-12, U-01~U-07 | REQ-100 1.1·3.2절, REQ-101 1.1·3.1·4·5·9절, REQ-102 2.2·2.4·2.6·4·4.1·5절, RSC-SUB-10, RSC-PUB-03, RSC-NACL-06, REQ-103 1~3절, CLAUDE.md 4절, eks.tfvars |
| DEC-080 | 2026-09-17 | 유효 | — | 문서 간 충돌 해소 | **정의 문서 쪽으로 통일**. (1) 경로 대상 택일 검사는 `route_tables` 의 `validation` 이다. 이 검사를 `precondition` 대상으로 적은 DEC-071 을 정정하며, `precondition` 대상은 RSC-PUB-04·RSC-VPCE-07 과 서브넷의 `route_table` 참조다. (2) REQ-100 2절 출력 규칙에 편의 출력 예외를 둔다. `shared_network.*`·`stacks.<stack>.*` 는 그 범위 안에서 유일한 이름을 키로 쓴다(DEC-053). (3) examples 검증 스택의 plan 입력은 기준 tfvars(`-var-file`)다. README Usage 는 구현 후 그 입력에서 파생하며 검증 입력으로 삼지 않는다. (4) TST-21 을 둘로 나누고 `nat_gateways = {}` + ENI 경로 입력을 TST-29 로 둔다. full.tfvars 는 NAT 2개를 선언하므로 NAT 0개 `assert` 를 담을 수 없다. (5) RSC-NAT-01 의 EIP 생성을 `eip_allocation_id` 가 없을 때로 한정해 RSC-NAT-03 과 맞춘다. (6) 태그 병합 순서와 보호 키의 정의는 REQ-101 8.1절 하나이며 REQ-100 2절은 참조만 둔다. (7) 이름 규칙의 `<키>` 는 리소스 키 전체가 아니라 마지막 마디다. 2.2절 표의 열 이름을 "이름 출처" 로 바꾸고 서브넷·NACL 행을 이름 기준으로 적는다. (8) `context` 는 필수 필드라도 값이 `null` 일 수 있으므로 `pri_domain`·`region` 을 쓰는 시점에 실패시킨다. `region` 검사는 `aws_vpc_endpoint` 의 `precondition` 으로 4.1.2절에 추가한다(RSC-VPCE-02). (9) REQ-101 8.1절 3단계 나열에 `shared_public.tags` 를 넣는다. (10) REQ-100 의 예시와 절 번호 참조는 이 저장소 기준이며 다른 저장소로 옮길 때 교체한다는 단서를 1절에 둔다. DEC-076 의 "그대로 쓸 수 있다" 를 정정한다. 근거는 `docs/report.md` C-01~C-10 | REQ-100 1·2·5.2·5.4절, REQ-101 8.1·9절, REQ-102 2.2·2.4·4.1.2·5.2절, RSC-NAT-01, RSC-VPCE-02, DEC-071·DEC-076 정정 |
| DEC-081 | 2026-09-17 | 유효 | — | VGW 경로 전파 선언 위치 | **Route Table 의 `propagate_vgw` 로 이전**. `vpn_gateway.propagate_to` 입력을 두지 않고 각 Route Table 이 `propagate_vgw = true` 로 전파를 켠다. 전파 리소스는 그 RT 키로 만든다(RSC-RT-11). 상위가 하위를 나열하는 입력을 두지 않는다는 참조 방향 원칙(REQ-100 3.1절)에 맞춘 것이며, DEC-016 과 DEC-058 (3) 의 `propagate_to` 를 번복한다. 이 전환은 DEC-063 의 반영 위치에만 암묵적으로 들어 있어 결정 행이 없었다. 근거는 `docs/report.md` G-07 | REQ-101 7.2절, RSC-VPN-01·03, RSC-RT-11, 4절 |
| DEC-082 | 2026-09-17 | 유효 | — | 테스트 실행 위치·명령·버전 | **`examples/<이름>/tests/*.tftest.hcl` 에서 `command = plan` 으로만 실행**. 루트 모듈에는 테스트 파일을 두지 않고 테스트는 검증 스택과 함께 git 에서 제외한다. 실제 AWS 호출 없이 돌리기 위해 `mock_provider "aws" {}` 를 쓰므로 로컬 Terraform CLI 는 1.7 이상이어야 하며, 테스트가 `examples/` 안에서만 돌므로 모듈의 `required_version` 하한 `1.5.7` 은 올리지 않는다. 로컬 CLI 가 하한과 같으면 테스트 단계를 건너뛰고 그 사실을 결과 보고에 적는다. DEC-076 이 "REQ-100 이 정의한다" 고만 적고 내용 결정 행이 없었다. 근거는 `docs/report.md` G-07 | REQ-100 5.1·5.2·5.3절, CLAUDE.md 4절 |
| DEC-083 | 2026-09-17 | 부분 대체 | DEC-092 | 리소스 요구사항 보완 | **누락 조건을 본문에 확정**. (1) NACL 룰의 `action` 은 `allow`·`deny`, `protocol` 은 `-1`·`tcp`·`udp`·`icmp`·`icmpv6` 와 대응 번호만 허용하고 `-1` 에 포트·ICMP 필드를 주면 plan 실패로 한다. (2) `vpc_endpoint_subnets` 의 제약을 `0.0.0.0/0` 에서 기본 경로(`0.0.0.0/0`, `::/0`) 없음으로 확장한다. `::/0` 만 가진 RT 로 Endpoint 서브넷이 인터넷에 나가는 빈틈을 막는다. (3) Endpoint 전용 SG 는 `enable_ipv6 = true` 이면 VPC IPv6 CIDR 의 443 인바운드도 허용한다. IPv6 워크로드가 Interface Endpoint 에 닿지 못하는 문제를 없앤다. (4) `stacks.<stack>.db_subnet_group_ids` 를 `_arns` 로 바꿔 ElastiCache 출력과 조합을 맞춘다. 출력 개명은 MAJOR 이므로 구현 전에 정리한다(RSC-OUT-06). (5) 2.2절 표에 "적용 대상" 열을 더해 `Name` 태그와 리소스 `name` 인자를 구분하고, `name` 인자 리소스의 최종 이름 길이는 모듈이 검사하지 않으며 호출자가 `context.name_prefix` 길이로 관리한다고 정한다. (6) 3.5절 표를 ID 순으로 정렬하고 4절 타입 골격을 모두 `optional(<타입>, <기본값>)` 표기로 통일하며 `서브넷Map`·`NACL` 약칭을 완전한 타입으로 적는다. 검증 항목 TST-30 을 더한다. 근거는 `docs/report.md` G-02~G-05, G-09~G-11 | 2.2, 3.5, 4절, 4.1.1·4.1.2, 5.2절, RSC-NACL-02, RSC-VPCE-04·07, 3.13, 세 tfvars |
| DEC-084 | 2026-09-17 | 유효 | — | 결정 기록 형식 | **`상태`·`대체` 열 추가**. 78개 행에 상태 열이 없어 어느 결정이 유효한지 전문을 읽어야 했다. 두 열은 후속 결정이 명시적으로 번복·대체·정정한 경우에만 채우고, 결정의 일부만 바뀐 경우 `부분 대체` 로 적는다. "기존 행은 고치지 않는다" 는 기록 규칙의 예외로 두 열만 후속 결정 반영 시 갱신한다. 근거는 `docs/report.md` G-06 | DECISIONS.md |
| DEC-085 | 2026-09-17 | 유효 | — | 2차 검토 충돌·구조 정리 | **정의 문서 쪽으로 통일**. (1) 입력의 스칼라 타입은 대응하는 AWS provider 인자 타입을 따른다. provider 6.64.0 스키마에서 `aws_vpc_dhcp_options.netbios_node_type`, `aws_customer_gateway.bgp_asn`, `aws_vpn_gateway.amazon_side_asn` 이 모두 문자열이므로 `netbios_node_type`·`bgp_asn`·`amazon_side_asn` 을 `string` 으로 받고 `full.tfvars`·`full_ipv6.tfvars` 의 ASN 값에 따옴표를 붙인다. 4.1.1절의 `netbios_node_type` 허용 값도 문자열 리터럴로 적는다. (2) RSC-OUT-01 에 편의 출력(`shared_network`, `stacks.<stack>`)이 범위 안의 이름을 키로 쓴다는 예외를 명시한다(DEC-053). (3) 2.2절 도입문을 "모든 리소스의 이름" 으로 고치고 `Name` 태그인지 리소스 `name` 인자인지는 표의 적용 대상 열이 정하게 한다(DEC-083 (5) 의 짝). (4) RSC-VPC-05 의 "IPv6 리소스 0개" 에 AWS 가 기본 NACL 에 두는 IPv6 허용 룰은 예외임을 적는다(RSC-DEF-03). (5) 태그 병합 2단계 자리의 일반 규칙과 단일 리소스 모듈 예시를 REQ-100 2절로 옮기고, REQ-101 8.1절은 이 모듈의 병합 대상만 정의한다. DEC-080 (6) 이 REQ-100 을 참조 한 줄로 줄이면서 일반 규칙이 리소스 정의서에만 남았던 것을 바로잡는다. (6) IPv6 기본 경로 선언 규칙을 REQ-101 4절(NAT 정책)에서 5절(Route Table 정책)로 옮기고, 2.3절 인스턴스별 `tags` 목록에 Shared Public 을 넣는다. 근거는 `docs/report.md` 2차 C-01~C-05, D-01~D-03 | REQ-100 2절, REQ-101 4·5·8.1절, REQ-102 2.2·2.3·4·4.1.1절, RSC-VPC-05, RSC-OUT-01, full.tfvars, full_ipv6.tfvars |
| DEC-086 | 2026-09-17 | 부분 대체 | DEC-090 | 모듈이 만드는 ENI | **`eni_interfaces` 입력 추가, 경로 대상에 `eni` 추가**. 서브넷에 `aws_network_interface` 를 만들고 Route Table 경로가 그 키를 가리킬 수 있게 한다. NAT 인스턴스·어플라이언스를 쓰는 VPC 에서 ENI 를 모듈이 먼저 만들어 두면 인스턴스를 교체해도 경로 대상과 사설 IP 가 그대로 남는다. 모듈 소유 대상은 키로, 호출자 소유 대상은 `*_id` 로 가리킨다는 DEC-065 를 그대로 따르므로 경로 객체는 `gateway`·`nat_gateway`·`eni`·`network_interface_id` 네 필드의 택일이 된다. `network_interface_id`(호출자 ENI)는 그대로 남는다. 입력 필드는 provider 인자에 1:1 로 대응시킨다(`subnet`→`subnet_id`, `private_ips`, `security_groups`, `source_dest_check`, `interface_type`, `description`). 초안의 `ip`·`type`(`ENA`/`EFA`/`EFA_ONLY`) 별칭은 채택하지 않는다. 별칭을 두면 `locals` 변환이 생기고 AWS 값과 어긋난다(REQ-100 3.1·4절). `interface_type` 은 `null`(ENA)·`efa`·`efa-only`·`branch`·`trunk` 다. 의존 순서는 `aws_subnet` → `aws_network_interface` → `aws_route` 로 참조만으로 성립하며 `depends_on` 이 필요 없다. **감수하는 제약**: ENI 가 인스턴스에 연결되기 전에는 그 경로로 트래픽이 흐르지 않고, 이 상태는 plan 에서 드러나지 않는다(RSC-ENI-09). `source_dest_check` 기본값 `true` 와 기본 SG 전면 차단(RSC-DEF-01)도 호출자가 값을 주지 않으면 통신이 막히는 지점이라 변수 설명에 명시한다. 인스턴스 연결·해제는 범위 밖이다. 근거는 `examples/dmz/terraform.tfvars` 초안과 provider 6.64.0 `aws_network_interface` 스키마 | REQ-101 2·4·5절, REQ-102 2.1~2.5, 3.6 신설, 3.7~3.14 로 절 이동, RSC-NAT-07, RSC-RT-01·02, 3.14 출력, 4·4.1절, 5.1·5.2절, CLAUDE.md 1절, full.tfvars, full_ipv6.tfvars |
| DEC-087 | 2026-09-17 | 부분 번복 | DEC-088 | 모듈이 만드는 Security Group | **`security_groups` 최상위 입력 추가, 룰은 범위 밖 유지**. ENI 에 붙일 SG 를 모듈이 만들고 `eni_interfaces.<key>.security_group_names` 가 그 키를 가리킨다. 호출자 SG 는 `security_group_ids` 로 계속 받으며 둘의 합집합이 `aws_network_interface.security_groups` 가 된다(DEC-065 의 키/ID 원칙). SG 룰은 만들지 않는다. `aws_security_group` 의 `ingress`·`egress` 는 provider 스키마에서 Optional+Computed 이므로 인라인 블록을 쓰지 않으면 호출자가 `aws_vpc_security_group_ingress_rule`·`egress_rule` 로 룰을 붙여도 이 모듈 plan 이 흔들리지 않는다. Route Table 에 외부 모듈이 경로를 넣는 RSC-RT-02 와 같은 구조다. 이로써 REQ-101 6절의 "SG 는 워크로드 모듈 책임" 은 "룰은 워크로드 모듈 책임, SG 리소스는 모듈이 만들 수 있다" 로 좁혀진다. **구조 결정**: 초안은 `eni_interfaces` 아래에 `security_groups` 와 `network_interfaces` 두 Map 을 두었으나, 입력 하나가 리소스 유형 하나를 맡는 이 모듈의 입력 모델(4절)과 2.1절 키 체계에 맞추어 `security_groups` 를 최상위 입력으로 분리한다. SG 는 ENI 에 종속되지 않고 여러 ENI 가 공유하며, 키 경로가 2단계가 되면 리소스 키·이름 규칙도 2단계가 된다. **감수하는 제약**: 만들어진 SG 는 룰이 없어 전면 차단이다. provider 가 생성 시점에 AWS 기본 아웃바운드 허용 룰을 회수하므로(RSC-SG-04) 호출자가 인바운드·아웃바운드를 모두 붙여야 한다. SG 이름은 VPC 안에서 유일해야 해 `vpce` 키를 예약한다(RSC-SG-02). `efa-only` ENI 는 IP 트래픽을 다루지 않아 경로 대상이 될 수 없다(RSC-ENI-11). 초안의 `sg_name`(단수)·`type`·`ip`·문자열 `"false"` 는 채택하지 않는다. AWS 인자는 SG 집합이고 나머지는 DEC-086 의 1:1 대응 원칙을 따른다 | REQ-101 2·4·6절, REQ-102 2.1~2.5, 3.6, 3.14, 4·4.1절, 5.2절, RSC-ENI-01·05·11, RSC-SG-01~05, CLAUDE.md 1절, full.tfvars, full_ipv6.tfvars |
| DEC-088 | 2026-09-17 | 유효 | — | Security Group 룰 | **모듈이 SG 룰까지 만든다. 룰은 이름을 키로 하는 Map 이고 독립 리소스다**. `security_groups.<key>.ingress`·`egress` 를 룰 이름 키의 Map 으로 받아 `aws_vpc_security_group_ingress_rule`·`egress_rule` 을 룰 하나당 1개 만든다. 키는 `<sg_key>/<direction>/<rule_name>` 으로 NACL 룰과 같은 형식이다. 인라인 `ingress`·`egress` 블록을 쓰지 않으므로 다른 모듈이 같은 SG 에 룰을 더해도 이 모듈 plan 이 흔들리지 않는다(RSC-RT-02 와 같은 원칙). DEC-087 의 "룰은 만들지 않는다" 를 번복하며, REQ-101 6절은 "포트 수준 접근 제어는 워크로드 모듈 책임, 단 모듈이 만드는 ENI 의 SG 는 예외" 가 된다. **초안에서 바꾼 것**: (1) 룰을 `list` 가 아니라 이름 키 Map 으로 받는다. `list` 는 인덱스가 리소스 키가 되어 중간 항목을 지우면 뒤 항목이 전부 재생성되므로 REQ-100 2절의 안정 키 규칙에 어긋난다. (2) `protocol = "HTTP"·"HTTPS"` 같은 응용 계층 별칭 대신 AWS 인자 값 `ip_protocol`(`-1`·`tcp`·`udp`·`icmp`·`icmpv6` 와 대응 번호)과 `from_port`·`to_port` 를 쓴다. 별칭은 `locals` 매핑을 만들고(REQ-100 4절 금지) 초안의 `{ protocol = "HTTPS", port = 587 }` 처럼 뜻과 값이 어긋나는 줄을 만든다. (3) `cidr` 하나 대신 AWS 의 소스 다섯 필드(`cidr_ipv4`, `cidr_ipv6`, `prefix_list_id`, `referenced_security_group_name`, `referenced_security_group_id`)를 택일로 둔다. 모듈 SG 는 키로, 호출자 SG 는 ID 로 가리킨다(DEC-065). (4) ENI 의 SG 참조는 단수 `sg_name` 이 아니라 집합 `security_group_names`·`security_group_ids` 다. AWS 인자가 집합이고 ENI 는 SG 를 여러 개 가질 수 있다. **감수하는 제약**: 룰을 비운 방향은 전부 차단이며 provider 가 AWS 기본 아웃바운드 허용 룰을 생성 시점에 회수한다(RSC-SG-05). `aws_security_group` 의 인라인 `ingress`·`egress` 는 Optional+Computed 라 plan 에서 미확정 값이므로 인라인 룰 수는 `assert` 대상이 아니다(TST-34) | REQ-101 6절, REQ-102 2.1·2.3·2.5, 3.6, 4·4.1절, 5.2절, RSC-SG-01~07, RSC-ENI-05, full.tfvars, full_ipv6.tfvars |
| DEC-089 | 2026-09-17 | 유효 | — | 3차 검토 충돌·누락 정리 | **입력 이름을 AWS 인자로 통일하고 plan 에 안 드러나는 제약을 표로 모은다**. (1) NACL 룰의 `action` 을 `rule_action` 으로 바꾼다. provider 인자가 `aws_network_acl_rule.rule_action` 이며, SG 룰(DEC-088)이 AWS 인자 이름을 그대로 쓰기로 한 규칙을 NACL 룰에도 같게 적용한다. 세 tfvars 의 룰 줄도 함께 고친다. (2) NACL·SG 룰의 프로토콜 허용 값을 문자열 리터럴(`"-1"`, `"tcp"`, `"6"` …)로 적어 타입 `string` 과 맞춘다. (3) SG 룰의 `icmp`·`icmpv6` 는 `from_port` 가 ICMP 타입, `to_port` 가 코드이며 없으면 plan 실패로 한다. AWS 가 포트 자리에 타입·코드를 받는 것을 규칙으로 명시한다. (4) 어떤 ENI 도 참조하지 않는 SG 도 선언된 대로 만든다(RSC-RT-03 과 같은 원칙). (5) 4.2절 "변수 `description` 에 적을 내용" 표를 신설한다. 본문에 흩어진 여덟 항목을 모으고 plan 에서 드러나지 않는 항목을 표시해, `description` 이 유일한 방어선인 곳을 구현·리뷰에서 놓치지 않게 한다. (6) 4.1.1·4.1.2 표에 행 ID(`V-01`…, `P-01`…)를 붙이고 실패 테스트 ID 를 `TST-F-<행 ID>` 로 정한다. 근거 요구사항 ID 는 한 검사에 여러 행이 대응해 ID 로 쓸 수 없었다. (7) `required_version` 하한 `>= 1.5.7` 을 REQ-100 5.3절의 요구사항으로 고정하고 4.1절이 그 절을 참조한다. 근거 파일 `versions.tf` 가 `old/` 로 옮겨져 현재 트리에 없기 때문이다. `CLAUDE.md` 2·3절도 현재 트리(루트 `*.tf` 없음, `old/` 보존)를 반영한다. (8) 그 밖: `vgw_attachment_id` 출력 추가, `Name` 을 갖지 않는 리소스 명시, 출력 `security_group_ids` 와 ENI 입력 필드의 동명이의 설명, TST-29 기준 입력 교정, TST-36·37 추가, REQ-103 의 SG 태그 문장 조정. 근거는 `docs/report.md` 3차 C-01·C-02, G-01~G-12 | REQ-100 5.3절, REQ-101 —, REQ-102 2.2·3.6·3.14·4.1·4.2·5.2·5.3절, RSC-NACL-02, RSC-SG-01·04, RSC-VPN-02, CLAUDE.md 2·3절, REQ-103 3절, `DECISIONS.md` 기록 규칙, 세 tfvars |
| DEC-090 | 2026-09-18 | 유효 | — | 3차 검토 중복·범위 정리 | **공통 규칙은 한 곳, 약칭은 뒤로, 허용 값은 쓰는 만큼만**. (1) 프로토콜 값과 포트·ICMP 규칙을 2.7절로 모으고 RSC-NACL-02·RSC-SG-04 는 참조만 둔다. 두 룰이 같은 규칙을 다르게 적기 시작한 것(ICMP 취급 누락)이 이 중복에서 나왔다. 필드 이름이 리소스마다 다른 부분(`protocol` 대 `ip_protocol`, `icmp_type`·`icmp_code` 대 포트 자리)은 2.7절이 한 문단으로 설명한다. (2) 4절 입력 표 앞을 차지하던 타입 약칭 블록을 4.3절로 옮기고 도입부는 한 줄 참조로 줄인다. 입력 표가 4절 첫 화면에 온다. (3) `interface_type` 허용 값을 `null`·`efa`·`efa-only` 로 좁힌다. `branch`·`trunk` 는 ECS·EKS 의 ENI 트렁킹 값이라 컨트롤러가 직접 만들며 이 모듈이 만드는 ENI 의 대상이 아니다. 필요해지면 그때 넓힌다. (4) REQ-100 3.3절 히어독 예시에 "작성 형식 예시이며 타입의 정본은 REQ-102 4·4.3절" 을 명시한다. 예시에 `nacl` 필드가 없어 정본과 달라 보이던 문제를 없앤다. 근거는 `docs/report.md` 3차 D-01·D-02, U-01·U-02 | REQ-100 3.3절, REQ-102 2.7 신설, 4절 도입부, 4.3 신설, RSC-NACL-02, RSC-SG-04, RSC-ENI-06, 4.1.1절 V-08·V-10·V-21 |
| DEC-091 | 2026-09-18 | 유효 | — | 기준 tfvars 보완 | **파일 간 정합을 복원하고 계획되지 않는 구성에 인덱스 주석을 단다**. (1) basic ⊂ full, basic_ipv6 = basic + IPv6, full_ipv6 = full + IPv6 관계(5.1절)가 깨져 있었다. basic·full 에 없던 스택 태그·모듈 공통 태그·`private_dns`·`resource_tags` 를 복원해 IPv4↔IPv6 쌍의 차이를 IPv6 항목으로만 한정한다(TST-25·26 전제). (2) full 의 `appl-a1` 이 모듈 ENI 경로 `appl-eni` 를 가리키게 해 어떤 서브넷도 참조하지 않던 RT 를 없앤다. `appl-c1` 은 호출자 ENI 경로 `appl` 을 그대로 가리켜 RSC-NAT-07 의 두 방식을 실제 서브넷이 모두 쓴다. Cross-AZ 경로는 생기지 않는다. (3) 모듈 SG 를 참조하는 룰 이름 `vpce-sg` 를 `mgmt-https` 로 고친다. Endpoint SG 와 무관한 이름이었다. (4) 다섯 파일에 `# [n]` 인덱스 주석을 두어 계획되지 않는 리소스(미참조 `mgmt` SG, a1 에만 있는 ENI, 인터넷 경로 없는 ops 계층)와 샘플 값(호출자 SG·ENI·EIP ID, Flow Log 버킷)의 의도와 개선 방향을 적는다. 인덱스는 파일마다 1 부터 시작한다. (5) eks.tfvars 에 Pod IP 확장(보조 CIDR + pod 서브넷), Interface Endpoint SG, Private Hosted Zone 의 개선 방향을 주석으로만 남기고 리소스는 더하지 않는다. TST-37 의 기준값이 흔들리지 않게 하기 위함이다 | basic.tfvars, basic_ipv6.tfvars, full.tfvars, full_ipv6.tfvars, eks.tfvars, REQ-102 5.1절 |
| DEC-092 | 2026-09-18 | 유효 | — | 태그 모델 축소, Endpoint SG 참조, SG 룰 수명주기, 4차 잔여 정리 | **(1) `resource_tags` 입력과 Billing Tag 요구사항을 모두 삭제한다.** 태그 병합은 `merge(context.tags, <사용자 커스텀 tags>, { Name })` 두 단계가 되고 리소스 유형별 태그 입력은 두지 않는다. REQ-101 8.2절(Billing / Cost Allocation Tag), 1절 목표 "스택별 비용 추적", 10절 완료 기준의 비용 구분 항목을 삭제하고, 태그의 용도(비용 배부·조직 식별)는 호출자가 정하며 모듈은 특정 용도의 키를 요구·검사하지 않는다고 8.1절에 적는다. DEC-037(Billing Tag 생성 주체)을 번복하고 DEC-020·043·044·045·052·083 의 `resource_tags` 관련 부분을 대체한다. (2) **G-03**: Interface Endpoint 도 ENI 와 같이 `security_group_names`(모듈 SG 키)와 `security_group_ids`(호출자 SG ID)를 받고 합집합을 붙인다. 둘 다 비면 Endpoint 전용 SG 를 만드는 RSC-VPCE-04 는 그대로다. 검사 P-23 을 더한다. (3) **G-02**: SG 룰은 키나 소속 SG 가 바뀌면 교체, `ip_protocol`·포트·소스·`description` 은 갱신이다. provider 가 `ModifySecurityGroupRules` 로 수정하기 때문이며 2.5절과 4.2절에 적는다. (4) 4차 리포트 잔여: REQ-101 1.1절 표의 출력 절 번호를 3.14 로 고치고 2.7·4.2·4.3 행을 더하며 "새 절이 유일 정의를 선언하거나 절 번호가 바뀌면 같은 변경에서 표를 갱신한다" 를 규칙으로 적는다(C-01, D-01). 예약 키(`shared-`, `vpce`)를 2.2절 한 곳에 모으고 RSC-SG-02·06 은 참조로 줄인다(D-02, D-03). 5.1절에 `eks.tfvars` 는 TST-37 전용임을 적고 TST-01 의 기준 입력을 "IPv4·IPv6 기준 입력 4종" 으로 명확히 한다(G-01). 4.2절 재생성 행을 변수·필드 단위로 쪼갠다(G-04). 3.14절에 룰 리소스는 출력하지 않음을 적는다(G-05). TST-36 의 `mgmt` 하드코딩을 일반화한다(U-01). 상태 열 누락(DEC-052·058·086)을 채우고 기록 규칙에 갱신 의무를 넣는다(G-06). 기준 입력 5종에서 `resource_tags` 블록과 Billing 문구를 제거한다 | REQ-100 1·2절, REQ-101 1·1.1·4·8·10절, REQ-102 1·2.2·2.3·2.5·3.14·4·4.1·4.2·5.1·5.2절, RSC-PUB-03, RSC-SG-02·06, RSC-VPCE-02·04, 다섯 tfvars, DECISIONS.md 기록 규칙 |
| DEC-093 | 2026-09-18 | 유효 | — | 모듈 재구현 | **REQ-100~103 을 루트 `*.tf` 15개로 구현했다.** `old/` 는 참고만 했고 재사용 가능한 코드가 거의 없어(입력 모델·키 체계가 다름) 새로 썼다. 구현 중 확정한 사항: (1) `locals` 는 중첩 Map 의 flatten 과 VPC 전역 검사 계산에만 쓰고 값 변환은 하지 않는다. 서브넷·경로·NACL 룰·SG 룰·Subnet Group 이 그 대상이다. REQ-100 4절의 "복잡한 구조 변환 금지" 는 이 flatten 을 허용하는 뜻으로 읽는다. (2) Terraform 의 논리 연산자 OR·AND 는 단락 평가를 하지 않아 "x 가 null 이면 참, 아니면 f(x)" 를 OR 로 적으면 null 에서 f(x) 가 평가되어 실패한다. null 가드는 모두 `x == null ? true : f(x)` 조건식으로 쓴다. `validation` 안의 조건식 두 갈래는 타입이 같아야 하므로 `[true]` 대신 `for … if` 필터로 건너뛴다. (3) CIDR 포함·겹침 검사(P-02)는 `cidrcontains` 가 없는 1.5.7 에서 `cidrhost`·`split`·`pow` 로 IPv4 를 정수로 바꿔 비교한다. (4) `aws_default_network_acl` 은 AWS 기본 허용 룰(100 IPv4, 101 IPv6)을 그대로 선언하고 `subnet_ids` 를 `ignore_changes` 로 둔다. 전용 NACL 이 없는 서브넷은 AWS 가 기본 NACL 에 붙이기 때문이다. `aws_default_security_group` 은 룰 블록 없이 채택해 전면 차단한다. (5) 서브넷은 보조 CIDR 연관에 `depends_on` 을 걸어 삭제 순서를 보장하고(RSC-VPC-03), NAT 는 IGW 에 `depends_on` 을 건다. (6) tfmodule-context 가 `aws_caller_identity` 를 호출해 자격 증명 없이는 plan 이 되지 않으므로, `examples/offline` 에 동등한 `context` 객체를 로컬에서 만드는 검증 스택을 둔다. `examples/basic` 은 REQ-101 1.1절대로 `module "ctx"` 를 쓴다. 검증 결과: `validate` 통과, 기준 입력 5종 offline plan 통과(basic 48, basic_ipv6 52, full 113, full_ipv6 128, eks 147 리소스), basic↔basic_ipv6 차이 4·full↔full_ipv6 차이 15 가 모두 IPv6 리소스, 부정 케이스 9종(서브넷 이름 중복, 미선언 NAT, Shared Public 의 igw 아닌 RT, `enable_ipv6=false`+`ipv6_index`, VPC 밖 CIDR, CIDR 겹침, 잘못된 NACL protocol, 보호 키 `Name`, DB 그룹 1 AZ) 모두 plan 실패. (7) 호출자가 full.tfvars 에서 `mgmt` SG 와 `mgmt-https` 룰을 지웠으므로 full_ipv6.tfvars 도 같게 맞추고, TST-36 의 기준 입력을 "basic + 룰 없는 SG 1개" 로 바꾼다. 제약: 로컬 CLI 가 1.5.7 이라 `terraform test`(1.7+) 는 실행하지 않았다(REQ-100 5.3절). 미연결 ENI 경로의 AWS 동작(RSC-ENI-09)은 apply 없이 확인할 수 없어 그대로 남는다 | versions.tf, variables-context.tf, variables.tf, locals.tf, vpc.tf, subnets.tf, route-tables.tf, nat.tf, eni.tf, nacl.tf, vpc-endpoints.tf, vpn.tf, flow-logs.tf, route53.tf, outputs.tf, README.md, CLAUDE.md 1~3절, full_ipv6.tfvars, REQ-102 TST-36 |
| DEC-094 | 2026-09-18 | 유효 | — | Subnet Group 네 유형 | **필드 이름을 단수로 바꾸고 Redshift·MemoryDB 를 같은 패턴으로 추가한다**. 스택 필드 `db_subnet_groups`·`elasticache_subnet_groups` 를 `db_subnet_group`·`elasticache_subnet_group` 으로 바꾸고, `redshift_subnet_group`(`aws_redshift_subnet_group`, 이름 접미어 `-rssng`)과 `memorydb_subnet_group`(`aws_memorydb_subnet_group`, `-mdsng`)을 더한다. 네 필드는 모두 그룹 이름을 키로 하고 서브넷 이름 집합을 값으로 하는 Map(선택, 기본 `{}`)이며 구조·검사·태그·수명주기 규칙이 같다. **멤버 수**: DB 만 2개 AZ 이상이 AWS 제약이고 나머지 셋은 1개 이상이다. Redshift·MemoryDB 는 AWS 가 서브넷 1개도 받으므로 모듈은 1개 이상만 검사하고, Multi-AZ 배포에 2개 AZ 이상이 필요하다는 점은 변수 설명으로 안내한다(RSC-SUB-11·12). **유형 간 독립**: 같은 서브넷이 여러 유형의 그룹에 속할 수 있고 유형이 다르면 그룹 이름이 같아도 이름 접미어가 달라 허용한다. 이름 중복 검사는 같은 유형 안에서만 한다(RSC-SUB-13). provider 6.64.0 스키마에서 네 리소스가 `name`·`description`·`subnet_ids`·`tags` 로 같은 모양이라 리소스 블록도 같은 형태로 쓴다. 출력은 `stacks.<stack>.<type>_subnet_group_names`·`_arns` 네 쌍이다. 기준 입력은 basic 이 DB·ElastiCache 를, full·full_ipv6 가 네 유형을 모두 담는다. `docs/additional-Implementation-items.md` 1절의 Redshift 미구현 항목이 이 결정으로 해소된다 | REQ-100 3.3절, REQ-102 1·2.1·2.2·2.3·2.4·2.5·3.4·3.14·4·4.1·5.1·5.2절, RSC-SUB-05·09·11·12·13, REQ-103 3·4절, variables.tf, locals.tf, subnets.tf, outputs.tf, README.md, full.tfvars, full_ipv6.tfvars |
| DEC-095 | 2026-09-18 | 유효 | — | 구현 평가 후속 정리 | **검사 위치 사각지대를 규칙으로 못 박고 문서 공백 5건을 메운다**. (1) 리소스 인자가 다른 리소스를 키로 조회하는 값(ENI·Interface Endpoint 의 `security_group_names` → `aws_security_group`)은 `locals` 에서 존재하는 키만 남겨 조회하고 키 존재 검사는 `precondition` 에 둔다. 걸러내지 않으면 `locals` 평가가 `precondition` 보다 먼저 실패해 요구사항이 정한 메시지 대신 `Invalid index` 내부 오류만 나왔다. 4.1절 규칙으로 적고 `eni.tf`·`vpc-endpoints.tf` 를 고쳤다. (2) 4.2절 체크리스트 중 실제 변수 `description` 에 빠져 있던 다섯 항목을 채운다. `shared_public`·`stack_subnets` 의 IPv6 대응 NACL 룰 경고, `stack_subnets`·`vpc_endpoint_subnets` 의 재생성 조건, `context.name_prefix` 길이(가장 짧은 제약은 IAM 롤 64자). (3) RSC-DEF-03 에 기본 NACL 의 `subnet_ids` 를 모듈이 관리하지 않는다(`ignore_changes`)를 명시한다. 관리하면 AWS 가 자동으로 붙인 연결을 회수해 전용 NACL 이 없는 서브넷이 어느 NACL 에도 속하지 않는다. (4) 2.4절에 `secondary_cidrs` 항목끼리·`vpc_cidr` 과의 겹침은 검사하지 않는다고 적는다. AWS 가 연관 생성에서 거부한다(RSC-ENI-03 과 같은 원칙). (5) RSC-NAT-01 에 `connectivity_type` 은 `public` 고정이고 Private NAT Gateway 는 범위 밖임을, RSC-SUB-11·12 에 Redshift·MemoryDB 이름 제약과 길이 미검사를 적는다. 근거는 구현 평가(요구 대비 리소스·출력 100% 충족, 결함 1건·description 미이행 5건·요구 공백 5건) | REQ-102 2.4·4.1.2절, RSC-DEF-03, RSC-NAT-01, RSC-SUB-11·12, eni.tf, vpc-endpoints.tf, variables.tf, variables-context.tf |
| DEC-096 | 2026-09-19 | 유효 | — | 테스트 위치·명령, 판정 수단, `context` null 필드 검사 | **`terraform test` 를 모듈 루트 `tests/` 로 옮기고 `mock_provider` 아래에서 `command = apply` 를 허용한다.** DEC-093 의 제약(로컬 CLI 1.5.7)이 풀려 테스트를 실제로 쓰면서 REQ-100 5.2절의 세 규칙이 5.2절 TST 표와 충돌하는 것이 드러났다. (1) **위치**: `examples/<이름>/tests/` 에 두면 `assert` 가 자식 모듈(`module "vpc"`)의 리소스에 닿지 않아 출력으로 드러나는 항목만 검증할 수 있다. TST 38개 중 절반 이상이 리소스 속성을 보므로 테스트를 모듈 루트 `tests/` 로 옮기고 `examples/` 는 `plan` 전용 검증 스택으로 남긴다. (2) **`command`**: `command = plan` 에서는 리소스 ID 가 미확정이라 "경로의 `nat_gateway_id` 가 그 키의 NAT"(TST-09·21·31·32) 류를 비교할 수 없다. `mock_provider` 를 선언한 파일의 `run` 에 한해 `command = apply` 를 허용한다. mock 상태에만 쓰므로 AWS 를 호출하지 않고 리소스도 만들지 않아 `CLAUDE.md` 의 apply 금지 대상이 아니다. 입력 검증만 보는 실패 케이스 `run` 은 `command = plan` 으로 둔다. (3) **기준 입력**: `requirements/<기준 입력>.tfvars` 는 `module "ctx"` 용 키를 함께 담고 있어 그대로는 모듈 입력이 되지 않는다. 해석된 `context` 객체를 담은 `tests/context.tfvars` 를 뒤에 붙여(뒤 var-file 이 앞을 덮어쓴다) 완성하고, `team`·`cost_center` 는 경고만 남기고 무시된다. (4) **판정 수단**: `terraform test` 에는 이전 상태와의 plan diff 를 `assert` 로 보는 수단이 없다. 5.2절 표에 **판정** 열(`test`·`plan`·`test + plan`)을 두어 "기존 리소스 변경 0건" 류는 REQ-100 5.2절 3·5단계의 `examples/` plan 결과로 판정한다고 명시한다. (5) **mock 한계**: `mock_provider` 는 Optional+Computed 속성을 임의 값으로 채우므로 "나머지 속성은 `null`"(TST-09·25·32) 같은 부정 단언이 성립하지 않는다. TST-34 에만 있던 예외를 5절 도입부의 일반 규칙으로 올리고, TST-25 는 `assign_ipv6_address_on_creation` 으로 대신 확인한다. (6) **`context` null 필드**: Gateway Endpoint 도 `com.amazonaws.<region>.<service>` 를 만드는데 P-20 이 Interface Endpoint 만 담고 있어 `region = null` 에서 요구 메시지 대신 문자열 보간 `null` 오류가 났다. `aws_vpc_endpoint.gateway` 에 precondition 을 더하고 RSC-VPCE-01 과 P-20 행을 양쪽으로 넓혔으며, 4.1.2절에 "`context` 의 null 가능 필드를 쓰는 리소스를 추가하면 그 리소스의 검사 행을 같은 변경에서 더한다" 를 규칙으로 적는다. (7) 구현 과정에서 드러난 결함 2건을 같은 변경에서 고쳤다. `local.subnet_key_by_name` 이 서브넷 이름 중복으로 먼저 터져 P-01 메시지를 가리던 것(그룹화 `...` 로 해소), ENI 의 `subnet_id` 직접 인덱싱이 P-17 을 가리던 것(DEC-095 패턴대로 `locals` 에서 존재하는 키만 조회). 근거는 `docs/review-and-supplementation.md` R-02~R-06, I-02 | REQ-100 5.1·5.2·5.3절, REQ-102 4.1.2·5절 도입부·5.2절, RSC-VPCE-01, P-20, CLAUDE.md 1·3·4절, locals.tf, eni.tf, vpc-endpoints.tf, tests/ |
| DEC-097 | 2026-09-19 | 유효 | — | Flow Log 다중 목적지 | **`flow_log` 을 목적지 Map 으로 바꾸고 목적지 리소스 생성을 모듈에서 뺀다.** `aws_flow_log` 은 목적지를 하나만 갖기 때문에 같은 VPC 를 CloudWatch·S3·Firehose 에 동시에 보내려면 목적지 수만큼 리소스가 필요하다. (1) **입력**: `flow_log = { destinations = map(object({ log_destination_arn, log_destination_type, iam_role_arn?, traffic_type?, max_aggregation_interval?, log_format?, destination_options? })) }` 로 바꾸고 `for_each = var.flow_log.destinations` 로 만든다. 정규화용 `locals` 를 두지 않고 입력 구조가 리소스 인자에 그대로 대응한다(REQ-100 4절). 목적지 Map 의 키가 리소스 키이자 `Name` 태그의 가운데 마디가 되어 이름은 `<prefix>-<destination_key>-vpc-flow` 다. (2) **지원 유형**: `cloud-watch-logs`·`s3`·`kinesis-data-firehose` 셋. 기존에는 앞의 둘만 받았다. (3) **목적지 리소스 생성 제거**: `create_log_group`·`retention_in_days`·`kms_key_id` 입력과 `aws_cloudwatch_log_group`·`aws_iam_role`·`aws_iam_role_policy` 세 리소스를 없앤다. 로그 그룹·버킷·Delivery Stream 과 그 IAM 롤·버킷 정책·KMS 키 정책은 그 리소스를 소유한 스택의 몫이고 이 모듈은 ARN 만 참조한다(RSC-FLOW-08). 출력 `flow_log_cloudwatch_log_group_arn`·`flow_log_cloudwatch_iam_role_arn` 과 `flow_log_id`·`flow_log_destination_arn` 이 사라지고 `flow_log_ids`·`flow_log_arns`·`flow_log_destination_arns` 세 Map 출력이 들어온다. **출력 삭제·개명이므로 REQ-100 2절 기준 MAJOR 다.** (4) **`destination_options`**: `s3` 목적지에만 허용하고 `dynamic` 블록으로 값이 있을 때만 렌더링한다. 객체 안 기본값은 `parquet`·Hive 파티션·시간별 파티션이며, 객체 자체를 생략하면 블록이 없어 AWS 기본값(`plain-text`)이 된다. 그래서 기준 tfvars 는 `destination_options = {}` 를 적어 세 기본값을 쓴다. (5) **`log_format`**: AWS v2~v5 의 29개 필드를 AWS 순서 그대로 기본값 문자열로 둔다. 원문 요구사항의 "28개" 는 실제 필드 수와 맞지 않아 29 로 정정했다(사용자 확인). 중앙 Athena 테이블 컬럼과 1:1 이므로 재정의는 그 테이블을 함께 바꿀 때만 한다. (6) **검사**: `destinations` 빈 Map 거부(V-26), 목적지 키 문자 규칙과 `log_destination_type`·`traffic_type`·`max_aggregation_interval` 허용 값(V-04), `destination_options` 는 `s3` 전용이고 `file_format` 허용 값(V-05). `iam_role_arn` 은 타입으로 판정이 갈리는 만큼만 검사한다(V-27). `cloud-watch-logs` 는 필수, `s3` 는 금지이며 둘 다 plan 에서 막는다. `kinesis-data-firehose` 만 검사하지 않는데, 같은 계정 전송에는 롤이 필요하고 교차 계정 전송에는 지정할 수 없는데 입력에 둘을 구분할 정보가 없기 때문이다. 이 한 가지 예외는 변수 설명으로 안내한다. (7) **기준 입력**: full·full_ipv6 는 `s3` 목적지 1개, eks 는 `cloud-watch-logs` + `s3` 2개로 다중 목적지 회귀를 담는다. eks 가 쓰던 `create_log_group = true` 는 기존 로그 그룹·롤 ARN 참조로 바뀐다. 검증 항목은 TST-22 를 다시 쓰고 TST-39(다중 목적지)를 더한다. 근거는 `requirements/vpc-flow-log-module-requirements.md`(반영 후 삭제) | REQ-102 2.1·2.2·2.3·3.12·3.14·4·4.1.1·4.2·5.1·5.2절, RSC-FLOW-01~08, V-04·05·26·27, TST-22·39, variables.tf, flow-logs.tf, outputs.tf, README.md, CLAUDE.md 1절, full.tfvars, full_ipv6.tfvars, eks.tfvars, tests/ |
| DEC-098 | 2026-09-19 | 유효 | — | v2.0.0 릴리스 정리 | **`docs/`·`old/`·`examples/` 를 저장소에서 지우고 남는 참조를 옮긴다.** 재구현이 끝나 세 디렉터리의 역할이 사라졌다. (1) `docs/` 는 재구현 기간의 검토 리포트·비교표·데모 문서였고 요구사항이 아니다. 다만 `docs/shared-service-access-policy.md` 만은 REQ-101 6절·RSC-NACL-01·RSC-SG-07 이 호출자 참고 예시로 가리키고 있었으므로, 내용을 README 의 "Shared Service 접근 정책 예시" 절로 옮기고 세 참조를 README 로 바꿨다. (2) `old/` 는 재구현 전 구현 보존본이며 요구사항의 근거가 아니었다(DEC-093). `CLAUDE.md` 1·3절의 보존 서술과 `fmt` 제외 대상 문구를 지운다. (3) `examples/` 는 원래 `.gitignore` 로 제외된 검증용 임시 스택이라 저장소 내용이 바뀌지 않는다. 평소에는 없고 검증할 때 만든다는 사실을 `CLAUDE.md` 3절과 REQ-100 5.2절에 적는다. 검증 절차(REQ-100 5.1·5.2절 3·5단계)는 그대로다. (4) 릴리스 버전은 **v2.0.0** 이다. 직전 태그 v1.0.2 대비 입력 모델 전체(스택 평면 서브넷 Map, 명시적 Route Table, `flow_log.destinations`)와 출력 이름이 바뀌었으므로 REQ-100 2절 기준 MAJOR 다 | CLAUDE.md 1·3·4절, REQ-100 5.1·5.2절, REQ-101 6절, REQ-102 RSC-NACL-01·RSC-SG-07, README.md, DECISIONS.md 기록 규칙 |
| DEC-099 | 2026-09-19 | 유효 | — | 검증 자산을 저장소에서 제외 | **저장소에는 모듈 본체와 요구사항 문서만 남기고 검증 자산은 로컬에 둔다.** `.gitignore` 에 `/tests/`, `/requirements/*.tfvars`, `/requirements/*.png` 를 더해 `/examples/` 와 같은 취급으로 만든다. 추적 대상은 모듈 `*.tf`, `requirements/*.md` 5개, `README.md`, `CLAUDE.md`, `LICENSE`, `.gitignore` 뿐이다. **근거**: 이 저장소는 재사용 모듈만 담는다는 원칙(`CLAUDE.md` 머리말)에 검증 자산은 포함되지 않고, 이미 `examples/` 가 같은 이유로 제외돼 있었다. **감수하는 제약과 그 보완**: 파일이 사라지면 문서가 검증을 재현할 수 있어야 한다. 그래서 (1) REQ-102 5.1절을 "파일 목록" 에서 **기준 입력 5종의 구성 명세**(이름·AZ 수·담아야 하는 것 표)로 다시 쓰고, (2) REQ-101 1.1절 우선순위 표에서 tfvars 5행을 빼고 "기준 입력 5종의 구성과 용도 → REQ-102 5.1" 한 행으로 대체하면서 검증 자산이 git 제외임을 명시하고 쓰임별 조합(examples / `terraform test`)을 표로 정리했다. (3) REQ-103 1절이 가리키던 `eks-architecture.png` 를 글 설명으로 바꾸고 4절의 `eks.tfvars` 참조를 "REQ-102 5.1절 `eks` 기준 입력" 으로 바꿨다. (4) README 검증 절을 clone 직후 돌아가는 단계(`fmt`·`validate`)와 로컬 자산이 필요한 단계(`test`·`plan`)로 나눴고, Usage 가 가리키던 tfvars 참조를 없앴다. (5) `CLAUDE.md` 1·2·3·4·6·7절의 디렉터리·명령·스테이징 서술을 같은 기준으로 맞췄다 | .gitignore, REQ-100 5.1·5.2·5.4절, REQ-101 1.1절, REQ-102 5.1절, REQ-103 1·4절, README.md, CLAUDE.md 1·2·3·4·6·7절 |
| DEC-100 | 2026-09-19 | 부분 대체 | DEC-103 | 요구사항 문서 세트 재구성 | **주제 기준 4문서 + 지도 1문서로 다시 나눈다.** 기존 `REQ-100`(코드 스타일)·`REQ-101`(기본)·`REQ-102`(리소스별)·`REQ-103`(EKS) 네 문서는 번호가 주제를 드러내지 않아 "어디를 봐야 하는지"를 문서 계층 표로만 알 수 있었고, REQ-102 한 문서가 요구사항·계약·검증 정책을 모두 담아 570줄을 넘었다. 조직 표준 템플릿의 권장 분리(REQUIREMENTS / ARCHITECTURE / POLICIES / DECISIONS)에 맞춰 **답하는 질문** 기준으로 다시 나눈다. `README.md`(문서 지도·읽는 순서·ID 체계), `REQUIREMENTS.md`(왜 존재하고 무엇을 만들며 어디까지 책임지는가 + RSC 정본), `ARCHITECTURE.md`(어떤 모델로 표현하고 무엇을 주고받는가 = 키·이름·입력·출력·context·EKS), `POLICIES.md`(어떤 규칙을 강제하는가 = 코드 컨벤션·이름·태그·보안 기본값·검증 배치·수명주기·비용·테스트·버전), `DECISIONS.md`. **ID는 바꾸지 않았다.** `RSC-*` 83개, `V-*` 27개, `P-*` 23개, `TST-*` 39개를 그대로 옮겼다. 코드 주석 32곳·테스트 150곳·이 문서 185곳이 이 ID를 가리키고 있어 재번호는 추적성만 잃는다. **새로 더한 것**: 목표 수준 요구사항 `REQ-01`~`REQ-24`(RFC 2119 MUST/SHOULD/MAY)를 스캔용 요약으로 두고 각 행이 `RSC-*` 를 가리키게 했다. Security by Default(POLICIES 5절), 비용 정책(8절), Anti-Patterns(11절), Definition of Done(REQUIREMENTS 7.1절), Convention over Configuration(POLICIES 1절)은 기존 문서에 흩어져 있거나 암묵적이던 내용을 표로 모은 것이다. **절 번호 매핑**: REQ-100 2→POLICIES 2, 3.1→2.1, 3.2→6.1, 3.3→2.2, 4→2.3, 5.1~5.3→9.1~9.3 · REQ-101 2→ARCHITECTURE 1, 3→2.1, 3.1→2.2, 4→4, 5→3, 6→5.1, 7.1→5.2, 7.2→5.3, 8·8.1→POLICIES 4, 9→ARCHITECTURE 10, 10→REQUIREMENTS 7 · REQ-102 2.1→ARCHITECTURE 6, 2.2→7, 2.3→POLICIES 4.1, 2.4→6.1, 2.5→7, 2.6→ARCHITECTURE 2.3, 2.7→8.3, 3.1~3.13→REQUIREMENTS 6.1~6.13, 3.14→ARCHITECTURE 9, 4→8.1, 4.1→POLICIES 6.2, 4.1.1→6.2.1, 4.1.2→6.2.2, 4.2→6.3, 4.3→ARCHITECTURE 8.2, 5.1→POLICIES 9.4, 5.2→9.5, 5.3→9.6 · REQ-103 2~4→ARCHITECTURE 11.1~11.3. 코드 주석 `*.tf` 14개 파일, `tests/` 4개 파일, 루트 `README.md`·`CLAUDE.md` 의 참조를 같은 변경에서 갱신했다 | requirements/README.md·REQUIREMENTS.md·ARCHITECTURE.md·POLICIES.md 신설, REQ-100~103 삭제, `*.tf` 주석, `tests/`, README.md, CLAUDE.md 1·3절 |
| DEC-101 | 2026-09-21 | 유효 | — | `context` 참조 버전 | **`v1.3.5` 이상만 허용**. 모듈 전체의 일관성을 위해 `context` 입력은 tfmodule-context `v1.3.5` 이상 버전의 출력만 받는다. 이 모듈이 쓰는 `name_prefix`·`tags`·`region`·`pri_domain` 등 출력 필드의 스키마가 `v1.3.5`에서 확정되었고, 여러 모듈이 같은 `context` 계약을 공유해야 이름·태그가 조직 전체에서 일관되기 때문이다. `v1.3.5` 미만을 참조하면 출력 스키마가 달라 8.1절의 `context` 타입이 값을 조용히 버리거나 다른 뜻으로 읽어 `validate`·`plan`이 실패하거나 태그가 조용히 누락될 수 있다. 검증은 `module "ctx"`의 `source`에 고정한 `?ref=` 태그를 리뷰하는 것과 하위 버전에서 `validate`·`plan`이 실패하는지 확인하는 것으로 한다. DEC-001·DEC-034의 "v1.3.5 출력" 서술을 "v1.3.5 이상"으로 구체화하는 정정이며, 두 행은 고치지 않고 이 행에만 관계를 남긴다 | ARCHITECTURE 10절, POLICIES 9.3절 |
| DEC-102 | 2026-09-21 | 유효 | — | 입력 모델 점검과 `context` 타입 정정 | **`context` 타입을 ARCHITECTURE 8.1절에 맞추고, 오입력이 plan 을 통과하던 자리 여덟 개를 검사로 막는다.** (1) **고친 결함**: `variables-context.tf` 의 `context` 타입이 8.1절과 달랐다. `project` 가 필수 `string`, `cost_center` 가 `optional(string)` 이고 `region_alias`·`env_alias` 가 없어, `project` 를 내지 않거나 `cost_center` 를 number 로 내는 tfmodule-context 출력이 plan 단계에서 거부됐다. `CLAUDE.md` 5절 4항대로 `tests/context_contract.tftest.hcl`(TST-40)을 먼저 써서 실패를 확인한 뒤 타입을 8.1절대로 고쳤고, `description` 의 "reference version v1.3.5" 를 DEC-101 에 맞춰 "v1.3.5 or later" 로 바꿨다. 출력 스키마는 그대로이므로 하위 호환 변경(MINOR)이다. (2) **더한 검사**: V-28(`context.name_prefix`·`tags` 가 `null`), V-29(경로 목적지 키의 CIDR 형식), V-30~V-35(외부 리소스 식별자 형식: `eipalloc-`, `sg-`, `vgw-`, `vpc-`). 모두 지금까지 plan 이 통과하고 apply 에서 AWS 가 거부하거나(V-29~V-35) Terraform 내부 오류만 나오던(V-28) 자리다. 실패 케이스 `TST-F-V-28`~`TST-F-V-35` 를 같이 넣었다. (3) **메시지**: 항목이 많은 입력(서브넷, NACL 룰, SG 룰, Subnet Group, 경로, 참조 키)의 `error_message` 가 걸린 키를 함께 내도록 고쳤다. 이를 위해 NACL 룰 검사를 셋, SG 룰 검사를 둘로 나눴다. 검사 자체와 ID 는 바뀌지 않는다. (4) **교훈**: `error_message` 는 조건이 참일 때도 평가되므로 그 안의 식도 `null` 안전해야 한다. `x != null && f(x)` 는 1.5.7 이 단락 평가를 하지 않아 `join`·`startswith` 가 `null` 에서 터지고, `coalesce(x, "")` 는 빈 문자열을 거부한다. DEC-093 (2) 와 같은 결론으로 `x == null ? false : f(x)` 만 쓴다. `terraform test`(1.14.5)에서는 드러나지 않고 1.5.7 plan 에서만 드러났으므로 두 버전으로 모두 확인한다. (5) **검증**: `fmt -check` 통과, `validate`(1.5.7) 통과, `terraform test`(1.14.5) 11개 파일 88 run 통과(기존 77 + 신규 11), 기준 입력 5종 `examples/offline` plan 이 변경 전후 리소스 수와 속성까지 동일(basic 48, basic_ipv6 52, full 113, full_ipv6 128, eks 147, 변경·재생성 0건). 이 수치는 DEC-093 기록과 같다. (6) **넘기지 않은 것**: 입력 계약을 바꿔야 하는 세 건은 구현하지 않고 제안으로 남겼다. 서브넷 줄의 `route_table`·`az` 반복을 그룹 기본값으로 줄이는 안(ARCHITECTURE 2.3 의 "한 줄만 읽어도 알 수 있다" 원칙과 충돌), NACL 룰 한 줄이 `cidr_block` 과 `ipv6_cidr_block` 을 함께 받아 룰 리소스 둘로 펴지는 안(RSC-NACL-05 의 IPv4·IPv6 짝 중복을 없애지만 리소스 키가 늘어 MAJOR), `customer_gateways.<key>.device_name` 과 `security_groups.<key>.description` 의 파생 기본값(기존 배포에 갱신·재생성을 일으켜 기각). 판단은 specialist 와 사용자 몫이다. (7) **덤으로 고친 버그**: V-20 의 `db_subnet_group` 검사가 `alltrue([... contains ...]) && length(distinct([for m in members : st.subnets[m].az])) >= 2` 라서, 같은 스택에 없는 멤버를 적으면 뒤 항이 `st.subnets[m]` 을 그대로 조회해 요구사항 메시지 대신 `Invalid index` 내부 오류가 났다. 단락 평가가 없는 것이 원인이며(4) 와 같은 뿌리다. `for ... if contains(keys(st.subnets), m)` 로 거른다. Terraform 1.14.5 의 `terraform test` 에서는 드러나지 않고 1.5.7 plan 에서만 드러나므로 판정은 POLICIES 9.2 3단계 plan 으로 한다 | variables-context.tf, variables.tf, route-tables.tf, subnets.tf, eni.tf, vpc-endpoints.tf, README.md, POLICIES 6.2.1·9.5절, tests/context_contract.tftest.hcl, tests/failures.tftest.hcl, requirements/*.tfvars, examples/offline, examples/basic |
| DEC-103 | 2026-09-21 | 유효 | — | 요구사항 문서 세트 재통합 | **5문서(README·REQUIREMENTS·ARCHITECTURE·POLICIES·DECISIONS)를 REQUIREMENTS·ARCHITECTURE 2문서로 재통합한다. DEC-100 의 "답하는 질문 기준 4+1 분리"를 부분 대체한다.** DEC-100 이후 구현·검증이 진행되며 POLICIES 한 문서가 REQUIREMENTS·ARCHITECTURE 양쪽에서 참조되는 "규칙" 절과 "검사 배치" 절을 동시에 담아, 리소스 요구사항 하나를 확인하려면 REQUIREMENTS(무엇을) → ARCHITECTURE(계약) → POLICIES(규칙·검사 배치) 세 문서를 오가야 했다(예: RSC-PUB-04 하나가 ARCHITECTURE 2.2·7절과 POLICIES 6.1·6.2절을 모두 가리켰다). DECISIONS 는 다른 네 문서 어디에서도 도달할 방법이 README 목록뿐이라 "왜?"를 찾을 때 문서 지도부터 열어야 했다. 이번 통합은 읽는 사람이 묻는 두 질문으로 문서를 나눈다. REQUIREMENTS 는 "무엇을 만족해야 하고 어떤 규칙을 강제하며 어떻게 검증하고 왜 그렇게 정했는가"(요구사항 + 정책 + 검증 항목 + 결정 기록), ARCHITECTURE 는 "어떤 모델로 표현하고 무엇을 주고받으며 코드는 어떻게 구성되고 검사는 어디에 놓이는가"(모델 + 계약 + 코드 구조 + 검사 배치)다. POLICIES 의 이름·태그·보안 기본값·수명주기·비용·버전·Anti-Patterns(1·3·4·5·7·8·10·11절)는 "규칙"이므로 REQUIREMENTS 7절로, 검증과 테스트 절차(9절)는 "어떻게 검증하는가"이므로 REQUIREMENTS 8절로 옮긴다. 반대로 코드 컨벤션(POLICIES 2절: `for_each`, 이름·태그 구현, 입력 변수 정의 규칙, 히어독, Terraform 설계 원칙)과 입력 검증·검사 배치(POLICIES 6절: `validation`·`precondition` 분류와 V-*·P-* 배치표)는 "코드가 어떻게 구성되고 검사가 어디에 놓이는가"에 해당해 ARCHITECTURE 12·9절로 옮긴다. DECISIONS 의 기록 규칙과 DEC-001~102 전체 표는 REQUIREMENTS 10절(부록)로 옮긴다. requirements/README.md 의 문서 지도·읽는 순서·ID 체계·주제별 정의 위치 표는 REQUIREMENTS 머리말로 흡수하고, "검증 자산은 저장소에 없다" 절은 이미 같은 내용을 담고 있던 (구)POLICIES 9.2절(현 REQUIREMENTS 8.2절) 서술로 정의를 일원화해 README 쪽 서술은 중복 제거했다. **ID는 바꾸지 않았다.** `RSC-*`·`V-*`·`P-*`·`TST-*`·`DEC-*` 전체가 그대로다. **절 번호 매핑(5문서 체제 → 2문서 체제)**: REQUIREMENTS(구) 1~4→REQUIREMENTS 1~4(하위 절 동일), 5→5, 6→6(6.1~6.14 동일), 7→9(7.1→9.1) · ARCHITECTURE(구) 1~5→ARCHITECTURE 1~5(하위 절 동일), 6→6, 7→7, 8→8(8.1~8.3 동일), 9(출력 계약)→10, 10(context 계약)→11, 11(EKS)→13(11.1~11.3→13.1~13.3) · POLICIES(구) 1→REQUIREMENTS 7.1, 2→ARCHITECTURE 12(2.1→12.1, 2.2→12.2, 2.3→12.3), 3→REQUIREMENTS 7.2, 4→REQUIREMENTS 7.3(4.1→7.3.1), 5→REQUIREMENTS 7.4, 6→ARCHITECTURE 9(6.1→9.1, 6.2→9.2[6.2.1→9.2.1, 6.2.2→9.2.2], 6.3→9.3), 7→REQUIREMENTS 7.5, 8→REQUIREMENTS 7.6, 9→REQUIREMENTS 8(9.1→8.1, 9.2→8.2, 9.3→8.3, 9.4→8.4, 9.5→8.5, 9.6→8.6), 10→REQUIREMENTS 7.7, 11→REQUIREMENTS 7.8 · requirements/README.md 전체(문서 지도·읽는 순서·ID 체계·주제별 정의 위치·검증 자산 안내)→REQUIREMENTS 머리말, "검증 자산은 저장소에 없다" 절은 REQUIREMENTS 8.2절 정의로 통합(중복 제거) · DECISIONS.md 기록 규칙과 DEC-001~102 표 전체→REQUIREMENTS 10절(부록). **같은 변경에서 함께 고친 것**: 통합 과정에서 발견한 두 가지 오래된 참조도 정정했다. (a) (구)POLICIES 9.6절이 실패 케이스 근거 표를 "4.1.1·6.2.2절"로 가리켰는데 `4.1.1`은 DEC-100 재구성 이전(REQ-102 4.1.1) 좌표가 그대로 남은 것이었다. 두 표 모두 새 ARCHITECTURE 9.2.1·9.2.2절로 고쳤다. (b) (구)POLICIES 9.5절 TST 표의 "근거" 열 일부가 같은 이유로 REQ-102 구좌표(`2.1`·`2.2`·`2.3`·`2.5`·`2.6`, 예: TST-02·04·11·15·27·31·34·35·37·38)를 그대로 쓰고 있었다. DEC-100 매핑표로 최종 목적지를 역산해(`2.1`→ARCHITECTURE 6, `2.2`→ARCHITECTURE 7, `2.3`→REQUIREMENTS 7.3.1, `2.5`→REQUIREMENTS 7.5, `2.6`→ARCHITECTURE 2.3) 새 절 번호로 교체했다. 두 정정 모두 표의 뜻은 바꾸지 않고 좌표만 현재 문서에 맞췄다. **참조 갱신**: 같은 변경에서 루트 `CLAUDE.md`(12곳 이상: 머리말, 2·3·4·5·7절), 루트 `README.md`(6곳), `*.tf` 주석(POLICIES 참조 4개 파일, DEC- 참조 1개 파일), `tests/*.tftest.hcl`(POLICIES 참조 3개 파일, DEC- 참조 2개 파일)의 `POLICIES n절`·`DECISIONS`·`DEC-nnn`·`requirements/README.md` 참조를 REQUIREMENTS·ARCHITECTURE 새 절 번호로 고쳤다. README.md·POLICIES.md·DECISIONS.md 세 파일은 이 통합 작업에서 내용을 옮긴 뒤 삭제 없이 남겨 두었으며, 삭제는 별도로 진행한다 | requirements/REQUIREMENTS.md·ARCHITECTURE.md 재작성, requirements/README.md·POLICIES.md·DECISIONS.md 내용 흡수(삭제는 별도 진행), `*.tf` 주석, `tests/*.tftest.hcl`, 루트 CLAUDE.md, 루트 README.md, DEC-100 상태·대체 갱신 |
| DEC-104 | 2026-09-21 | 부분 대체 | DEC-105 | VPC 구조 object 변수 구조 점검 | **현행 구조를 유지하고 하위 호환 정리 3건만 승인한다. 구조 이동은 다음 MAJOR 후보로 보류한다.** v2.0.0 이 `shared_public`·`vpc_endpoint_subnets`·`stack_subnets`·`route_tables`·`nat_gateways`·`vpc_endpoints` 의 현행 모델을 이미 공개했으므로 입력의 이름·위치를 바꾸는 개선은 모두 MAJOR 다(7.7절). **검토 결과**: (1) 호출자 입력에는 중복이 없다. 서브넷 한 줄에 `az`·`route_table` 을 매번 적는 것은 DEC-067 이 AZ 그룹 대신 택한 형식이고, NACL 룰 타입이 `shared_public`·`stack_subnets` 에 두 번 나오고 Subnet Group 네 필드가 같은 모양인 것은 HCL 에 타입 별칭이 없어 생기는 **모듈 코드의** 반복이지 호출자가 같은 값을 두 번 적는 자리가 아니다. (2) 불필요한 설정도 없다. `vpc_endpoint_subnets.<name>.route_table` 은 Endpoint ENI 가 트래픽을 내지 않아 기능상 없어도 되지만, 서브넷 객체 세 곳이 같은 모양이어야 한다는 ARCHITECTURE 2.3절과 "입력만 읽어도 서브넷의 경로가 드러난다"(ARCHITECTURE 3절)를 지키기 위해 유지한다. **검토 후 기각한 대안**: (a) NACL 을 최상위 `network_acls` Map 으로 올리고 스택·Shared Public 이 키로 참조하는 것 — 스택을 지우면 그 스택의 리소스만 사라지는 7.5절 수명주기가 깨지고(NACL 이 남는다) NACL 의 리소스 키·이름이 바뀌어 재생성된다. DEC-014 를 유지한다. (b) Subnet Group 네 필드를 `subnet_groups = map(object({ type, subnets }))` 하나로 합치는 것 — `type` 판별자와 그것으로 거르는 `locals` 변환이 생겨 ARCHITECTURE 12.3절에 어긋나고, 같은 이름을 유형별로 쓰는 RSC-SUB-13 을 잃는다. DEC-094 를 유지한다. (c) `security_group_names`·`security_group_ids` 를 `sg-` 접두어로 구분하는 한 필드로 합치는 것 — 호출자 키도 `sg-` 로 시작할 수 있어 값이 다의적이 된다. 기각. **승인한 하위 호환 정리(PATCH)**: (1) `vpc_endpoints` 기본값을 `null` 에서 `{}` 로 바꾸고 `nullable = false` 를 둔다. 두 필드가 모두 비어 있는 `{}` 와 `null` 은 뜻이 같고(둘 다 리소스 0개), 명시적 `null` 은 기본값으로 대체되므로 기존 호출이 그대로 동작하며 `locals`·`validation` 의 `== null ?` 분기가 사라진다. `shared_public`·`vpn_gateway`·`private_dns`·`dhcp_options`·`flow_log` 는 `{}` 가 "생성" 을 뜻하므로 `null` 을 유지한다. (2) `eni_interfaces` 와 `vpc_endpoints.interface` 의 `security_group_names`·`security_group_ids` 를 `optional(set(string))` 에서 `optional(set(string), [])` 로 바꿔 `coalesce()` 를 없앤다. 빈 집합과 `null` 은 RSC-ENI-05 에서 같은 뜻(인자를 넘기지 않음)이다. `private_ips` 는 `null`(AWS 자동 할당)과 `[]` 의 뜻이 달라 그대로 둔다. (3) `shared_public`·`stack_subnets` object 타입의 필드 순서를 `tags → subnets → nacl → Subnet Group` 으로 바꿔 읽는 순서와 맞춘다. object 필드 순서는 계약에 영향이 없다. 세 정리는 V-*·P-* 표, 리소스 키, 이름 규칙을 바꾸지 않는다. **다음 MAJOR 후보로 보류**: `vpc_endpoint_subnets` 를 `vpc_endpoints.subnets` 로 옮겨 P-19 를 한 변수 안의 `validation` 으로 내리는 것, `flow_log = { destinations = map }` 의 한 겹을 벗겨 `flow_logs = map` 으로 두는 것(빈 Map 이 0개를 뜻하는 `nat_gateways` 와 같은 관례), `stack_subnets` 를 출력 이름과 같은 `stacks` 로 개명하는 것. 셋 모두 단독으로는 MAJOR 를 올릴 가치가 없으므로 다음 MAJOR 가 필요해지는 시점에 함께 넣고, 그때 이 행의 상태를 갱신한다 | ARCHITECTURE 8.1절 `shared_public`·`stack_subnets`·`eni_interfaces`·`vpc_endpoints` 행, ARCHITECTURE 12.2절 예시, RSC-ENI-01, RSC-VPCE-02, variables.tf, locals.tf, eni.tf, vpc-endpoints.tf, README Input 표 |
| DEC-105 | 2026-09-21 | 유효 | — | `flow_log` 평면화와 DEC-104 정리 3건 구현 | **DEC-104 가 승인한 하위 호환 정리 3건을 코드에 반영하고, 보류했던 MAJOR 후보 중 `flow_log` 평면화 하나만 꺼내 함께 넣는다.** DEC-104 는 세 MAJOR 후보를 "단독으로는 MAJOR 를 올릴 가치가 없다"며 보류했으나, 사용자가 `flow_log` 의 `destinations` 한 겹을 벗기라고 명시적으로 지시해 보류 사유가 그 항목에 한해 해소되었다. **구현한 하위 호환 정리(DEC-104 승인분)**: (1) `vpc_endpoints` 를 `default = {}` + `nullable = false` 로 바꾸고 `locals.vpc_endpoints_gateway`·`vpc_endpoints_interface` 두 local 과 `validation` 두 개의 `== null ?` 분기를 없앴다. (2) `eni_interfaces` 와 `vpc_endpoints.interface` 의 `security_group_names`·`security_group_ids` 를 `optional(set(string), [])` 로 바꿔 `eni.tf`·`vpc-endpoints.tf`·`variables.tf` 의 `coalesce()` 8곳을 없앴다. `private_ips` 는 `null`(AWS 자동 할당)과 `[]` 의 뜻이 달라 그대로 뒀다. (3) `shared_public`·`stack_subnets` object 필드 순서를 `tags → subnets → nacl → Subnet Group` 으로 맞췄다. 이 순서는 ARCHITECTURE 8.1·12.2 절이 이미 그렇게 적고 있었고 코드만 뒤처져 있었다. 두 전제를 1.5.7 과 1.14.5 에서 `terraform console` 로 실측해 확인했다. `nullable = false` 인 변수에 명시적 `null` 을 넘기면 기본값으로 대체되고, object 안 `optional(set(string), [])` 에 명시적 `null` 을 넣어도 `[]` 로 대체된다. **구현한 Breaking Change**: `flow_log = { destinations = map(...) }` 를 평면 Map `flow_logs = map(...)`(기본 `{}`)로 바꿨다. 빈 Map 이 0개를 뜻하는 것은 `nat_gateways`·`eni_interfaces`·`customer_gateways` 와 같은 관례이므로 `nullable = false` 를 따로 두지 않아 그 입력들과 형태를 맞췄다. 이름은 DEC-104 가 후보로 적어 둔 `flow_logs` 를 그대로 쓴다. 이에 따라 **V-26(`flow_log` 가 `null` 이 아닌데 `destinations` 가 비어 있음)을 삭제**했다. 빈 Map 이 0개라는 정상 입력이 되어 검사 대상 자체가 사라졌기 때문이며, ID `V-26` 은 재사용하지 않는다. V-04·V-05·V-27 은 대상 변수 이름만 `flow_logs` 로 바뀌었고 조건과 메시지는 같다. 리소스 키·이름 규칙·출력(`flow_log_ids`·`flow_log_arns`·`flow_log_destination_arns`)은 모두 그대로이므로 **출력은 Breaking Change 가 아니고 입력 표면만 깨진다**. 호출자 이주는 `flow_log = { destinations = { X } }` 를 `flow_logs = { X }` 로 바꾸는 것뿐이며 `moved` 블록이 필요 없다. **검증**: `terraform fmt -check *.tf` 통과, 1.5.7 `validate` 통과, `terraform test`(CLI 1.14.5) 12개 파일 93건 통과(기존 11개 파일 87건 + 새 `tests/nullable_defaults.tftest.hcl` 6건). 기존 `failures.tftest.hcl` 은 V-26 삭제로 `run` 하나가 줄어 65건에서 64건이 되었다. 기준 입력 5종을 `examples/offline` 에서 plan 해 리팩터링 전 모듈 사본과 **리소스 주소 집합·plan 속성값이 5종 모두 0줄 차이**임을 확인했다(basic 48, basic_ipv6 52, full 115, full_ipv6 124, eks 139 리소스, 삭제·재생성 0건). **버전 분류**: 입력 변수 이름·구조 변경이므로 7.7 절 기준 MAJOR(`v3.0.0`) 이며 확정은 specialist 판정에 따른다. **여전히 보류**: `vpc_endpoint_subnets` 를 `vpc_endpoints.subnets` 로 옮기는 것(P-19 를 `validation` 으로 내림)과 `stack_subnets` 를 `stacks` 로 개명하는 것 두 건은 사용자 지시 범위 밖이라 이번에 손대지 않았다. 같은 MAJOR 에 묶으면 호출자 이주가 한 번으로 끝난다는 이점이 있으므로 `v3.0.0` 을 확정하기 전에 specialist 가 함께 판정한다. **재구성한 로컬 검증 자산**: 8.4 절 기준 입력 5종(`requirements/*.tfvars`)이 트리에서 사라져 있어 `tests/` 의 단언과 8.4 절 표에서 역으로 재구성했다. `basic`·`basic_ipv6` 는 DEC-093 이 기록한 리소스 수(48·52)와 일치하나 `full`·`full_ipv6`·`eks` 는 원본과 다른 수(113→115, 128→124, 147→139)이므로 8.4 절이 요구하는 구성 요소는 모두 갖췄지만 원본과 동일한 파일은 아니다 | variables.tf, locals.tf, eni.tf, vpc-endpoints.tf, flow-logs.tf, outputs.tf, ARCHITECTURE 6·7·8.1·9.2.1·9.3·10절, REQUIREMENTS 6.12·7.6·8.4·8.5절, README Usage·Input 표, tests/failures.tftest.hcl, tests/nullable_defaults.tftest.hcl, requirements/*.tfvars, examples/basic, examples/offline |
| DEC-106 | 2026-09-21 | 유효 | — | `flow_logs` 리팩터링 specialist 판정과 릴리스 게이트 | **DEC-105 가 남긴 미결 네 가지를 판정한다.** (1) **변수명**: `flow_logs` 유지를 권고한다(최종 결정은 사용자 몫). `nat_gateways`·`customer_gateways`·`eni_interfaces`·`security_groups` 등 이 모듈의 모든 복수 리소스 입력이 "만드는 리소스의 복수형"으로 이름 붙는 관례를 따르고, ARCHITECTURE 6·7절 리소스 키·이름 규칙 표가 이미 `flow_logs`를 전제로 적혀 있으며(DEC-097 이후), 출력 `flow_log_ids`·`flow_log_arns`·`flow_log_destination_arns`와 어간이 맞아 입출력 대칭이 유지된다. `flow_log_destinations`는 이 모듈에 없는 "_destinations" 접미 관례를 새로 만들고 정본 표(ARCHITECTURE 6·7절)를 다시 고쳐야 한다. (2) **보류 중인 파괴적 변경 2건(`vpc_endpoint_subnets`→`vpc_endpoints.subnets`, `stack_subnets`→`stacks`)은 이번 `v3.0.0`에 넣지 않는다.** 사용자 지시 범위는 `flow_log` 평면화 하나였고(`CLAUDE.md` 5절 2항의 관련 코드만 리팩터링 원칙), (4)의 기준 입력 무결성 문제로 "기존 리소스 변경 0건"을 신뢰 있게 입증할 기준선이 흔들린 상태에서 구조 변경 2건을 더 얹으면 회귀 위험이 지금 가진 검증 능력 밖으로 쌓인다. DEC-104 의 보류는 그대로 유지하며 다음 MAJOR 후보로 남긴다. (3) **버전은 `v3.0.0`(MAJOR)으로 확정한다.** `flow_log`→`flow_logs`는 입력 변수의 이름·구조 변경이므로 [7.7절](#77-버전과-호환성) Breaking Change 정의(입력 변수 제거·이름 변경·의미 변경)에 해당하고, DEC-104 승인분 3건(`vpc_endpoints` 기본값, ENI·Endpoint SG 필드 기본값, 필드 순서)은 하위 호환이라 버전 판단에 영향이 없다. (4) **기준 입력 5종의 검증 증거는 조건부로 유효하며 `v3.0.0` 태그는 보류한다.** 재구성본과 리팩터링 전 모듈 사본의 plan 비교(리소스 주소·속성값 0줄 차이)는 "이번 코드 변경이 리소스를 흔들지 않았다"는 자기 일관적 증거로는 유효하며, 이 근거로 `flow_logs` 변경과 DEC-104 정리 3건 자체의 무해성은 인정한다. 그러나 `full`·`full_ipv6`·`eks` 재구성본이 DEC-093·DEC-102가 같은 날(2026-09-21) 재확인한 값(113/128/147)과 다른 값(115/124/139)을 내는 것은, 8.4절이 요구하는 "구성 요소"는 갖췄어도 원본과 동일한 파일이 아니라는 뜻이며 그 차이가 무엇인지 아무도 특정하지 못한 상태다. 8.5절 TST 항목은 상대 비교(예: NAT 수 = `nat_gateways` 항목 수)라 이 격차로 실패하지는 않지만, TST 표가 전제하는 "요구사항이 정한 시나리오 전체가 fixture 에 있다"는 신뢰는 테스트 통과만으로 복원되지 않는다. **DEC-093·DEC-102 가 기록한 수치는 고치지 않는다.** 재구성본 수치로 덮어쓰면 실재하는 격차를 지우는 것이 되기 때문이다. `v3.0.0` 태그는 다음 중 하나가 끝나기 전까지 보류한다: (a) 원본과 일치하는 `requirements/*.tfvars` 5종을 복구하거나, (b) `full`·`full_ipv6`·`eks` 재구성본을 8.4절 표 항목별로 engineer 가 수동 대조해 무엇이 더해지거나 빠졌는지 특정하고 그 결과를 specialist 가 재검토해 새 결정으로 남긴다. 이 게이트는 코드(`*.tf`, 요구사항 문서)의 커밋·병합을 막지 않는다. 그 자산들은 로컬 검증 전용이며 저장소에 들어가지 않는다([8.2절](#82-절차)). 이 결정은 DEC-104·DEC-105 의 내용을 번복하지 않으므로 두 행의 상태·대체 열은 갱신하지 않는다 | ARCHITECTURE 6·7절(변수명 근거), [7.7절](#77-버전과-호환성), [8.4절](#84-기준-입력), [8.5절](#85-검증-항목), [9절](#9-완료-기준) Definition of Done |
