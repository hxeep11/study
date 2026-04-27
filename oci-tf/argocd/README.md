# Argo CD Applications

이 디렉터리는 OKE 클러스터의 Argo CD에 등록할 Application 매니페스트를 보관한다.

## wiz-test-seunghun

- Application: `wiz-test-seunghun`
- AppProject: `wiz-test-seunghun`
- Source repo: `http://158.101.80.134:8080/wiz/test/wiz-test-seunghun.git`
- Source path: `auth_system/k8s`
- Destination namespace: `wiz-test-seunghun`

적용 순서:

```bash
kubectl apply -f gitlab-repo-secret.yaml
kubectl apply -k argocd/applications
```

주의:

- `gitlab-repo-secret.yaml`이 먼저 적용되어야 Argo CD repo-server가 GitLab 저장소를 읽을 수 있다.
- `wiz-test-seunghun` 저장소의 `auth_system/k8s` 경로에 Kubernetes 매니페스트나 Kustomize 구성이 커밋되어 있어야 실제 sync가 성공한다.
- 앱 컨테이너 이미지는 Argo CD가 빌드하지 않는다. 이미지 빌드/푸시 파이프라인을 별도로 준비한 뒤 `auth_system/k8s`에서 해당 이미지를 참조해야 한다.
