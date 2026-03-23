apiVersion: v1
kind: Config
clusters:
- name: ${cluster_name}
  cluster:
    server: ${cluster_endpoint}
    certificate-authority-data: ${cluster_ca}
contexts:
- name: ${cluster_name}
  context:
    cluster: ${cluster_name}
    user: ${cluster_name}
current-context: ${cluster_name}
users:
- name: ${cluster_name}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: gcloud
      args:
        - container
        - clusters
        - get-credentials
        - ${cluster_name}
        - --region=${region}
        - --project=${project_id}
      interactiveMode: IfAvailable
      provideClusterInfo: true
