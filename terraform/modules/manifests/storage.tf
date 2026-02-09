
############################################
# STORAGE CLASSES
############################################
resource "kubectl_manifest" "mongo_storageclass" {
  yaml_body = <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: mongo-gp3
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  encrypted: "true"
  
EOF
}

resource "kubectl_manifest" "mysql_storageclass" {
  yaml_body = <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: mysql-gp3
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  encrypted: "true"
  
EOF
}

resource "kubectl_manifest" "storageclass_redis" {
  yaml_body = <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: redis-gp3
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  encrypted: "true"
  
EOF
}
