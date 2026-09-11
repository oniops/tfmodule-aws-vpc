# AWS VPC Terraform 모듈 - EKS Stack 서브넷 태그 안내

<!-- 문서 계층: REQ-101(BASE, 공통 전제) → REQ-102(RSC, 리소스별 요구사항) → REQ-103(EKS, 이 문서: EKS 스택 태그 안내). 모듈은 이 세 문서를 기준으로 새로 구현한다. 현재 저장소의 코드와 README는 참고 자료이며 요구사항의 근거가 아니다. 작성일 2026-09-10, 개정 2026-09-11. -->

## 1. 목적

본 문서는 REQ-101·REQ-102로 정의한 VPC 모듈 위에 EKS 클러스터를 올릴 때 서브넷에 필요한 태그를 안내한다. 모듈은 EKS를 위한 별도 입력이나 자동 태그를 두지 않으며, 아래 태그는 호출자가 `stack_subnets.<stack>.subnets.<role>.<az>.tags`와 `public_subnets.<az>.tags`에 직접 정의한다.

Subnet, AZ, NAT Gateway, Route Table, NACL, 태그 병합, Billing Tag 및 Stack 수명주기는 REQ-101·REQ-102를 따르며 여기서 다시 정의하지 않는다. 충돌 시 REQ-101, REQ-102 순으로 우선한다.

## 2. EKS Stack 기본 원칙

- EKS 스택은 다른 스택과 같은 `stack_subnets` 항목이다. 스택을 구분하는 입력은 없으며 태그로만 구별된다.
- 새 Role, 라우팅, NAT, NACL 규칙을 도입하지 않는다. 노드·Pod·Internal LB는 `private`, Internet-facing LB는 `public`(Shared 또는 스택 전용), 데이터 계층은 `database`에 둔다.
- 모듈은 호출자가 정의한 태그를 REQ-101 8.1절 3단계로 병합해 그대로 적용하고, 보호 키(`Name`, `Stack`, `ResourceScope`, `ManagedBy`)만 검사한다. `kubernetes.io/*`, `karpenter.sh/*` 키는 생성·검사하지 않는다.
- EKS 스택은 특정 애플리케이션명이나 업무 도메인에 종속되지 않아야 한다.

## 3. Role별 권장 태그

| 대상 | 태그 | 값 | 필요 조건 |
| --- | --- | --- | --- |
| `private` AZ 그룹 | `kubernetes.io/role/internal-elb` | `1` | AWS Load Balancer Controller가 Internal LB 서브넷을 자동 탐색할 때 |
| `private` AZ 그룹 | `karpenter.sh/discovery` | `<cluster_name>` | Karpenter 사용 시. Node가 생성될 서브넷에만 |
| Public AZ 그룹(Shared 또는 스택 전용) | `kubernetes.io/role/elb` | `1` | Internet-facing LB 서브넷 자동 탐색 |
| 스택의 모든 AZ 그룹 | `kubernetes.io/cluster/<cluster_name>` | `shared` | 구버전 AWS Load Balancer Controller, 기존 조직 표준 등 호환성이 필요할 때만. 최신 EKS 구성에서는 불필요 |
| 스택의 모든 AZ 그룹 | `ClusterName` | `<cluster_name>` | 조직 식별용(선택) |

- `kubernetes.io/role/elb`와 `kubernetes.io/role/internal-elb`는 값이 클러스터와 무관하므로 Shared Public Subnet에 붙여 여러 클러스터가 공유할 수 있다.
- 한 VPC에 EKS 스택이 여러 개면 `karpenter.sh/discovery`와 `kubernetes.io/cluster/*`는 스택마다 자기 `cluster_name`으로 정의한다. Shared Public Subnet을 여러 클러스터가 쓰면 각 클러스터의 `kubernetes.io/cluster/<cluster_name>` 태그를 함께 둘 수 있다.
- `database`, `intra`에는 EKS 태그를 두지 않는다.
- Karpenter가 탐색하는 Security Group 태그는 워크로드 모듈의 책임이며 이 모듈은 서브넷 태그만 다룬다.

## 4. 예시

```hcl
public_subnets = {
  "apne2-az1" = {
    route_table = "pub"
    subnets     = { pub-a1 = "10.230.10.0/24" }
    tags        = { "kubernetes.io/role/elb" = "1" }
  }
}

stack_subnets = {
  shop = {
    subnets = {
      private = {
        "apne2-az1" = {
          route_table = "pri-a1"
          subnets     = { node-a1 = "10.230.20.0/22" }
          tags = {
            "kubernetes.io/role/internal-elb" = "1"
            "karpenter.sh/discovery"          = "prod-shop-eks"
          }
        }
      }
    }
  }
}
```

## 5. EKS Private Network 요구사항

EKS Stack의 Private 통신 정책과 이 모듈의 구현 범위는 REQ-101 6절을 따르며 여기서 다시 정의하지 않는다. REQ-101 6절 정책을 EKS 구성 요소에 대응하면 다음과 같다.

- Toolchain Stack → EKS Private API Endpoint, Internal Deployment Endpoint
- EKS Workload → Observability Private Endpoint
- Peered VPC의 EKS → 중앙 Observability Private Endpoint(REQ-101 7.1절)

EKS 내부의 Pod-to-Pod 및 Namespace 접근 통제는 Kubernetes NetworkPolicy 등 Kubernetes 계층의 책임이다.

## 6. 완료 기준

REQ-101 10절, REQ-102 5절에 더해 다음을 만족해야 한다.

- 모듈에 EKS 스택을 위한 별도 입력이나 자동 태그가 없다.
- 호출자가 AZ 그룹 `tags`에 정의한 `kubernetes.io/*`, `karpenter.sh/*`, `ClusterName` 태그가 그 그룹의 모든 서브넷에 그대로 적용되고, 모듈이 값을 바꾸거나 추가·제거하지 않는다.
- 위 태그를 한 AZ 그룹에 추가·제거해도 다른 AZ 그룹과 다른 스택의 plan 결과는 변경 0건이다.
- Toolchain 및 Observability와의 통신은 REQ-101 6절 정책을 따른다.
