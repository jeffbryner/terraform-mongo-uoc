How to get started: 

1) Download terraform https://www.terraform.io/downloads.html
2) terraform init
3) download https://github.com/radekg/terraform-provisioner-ansible/releases
4) mkdir ~/.terraform.d/plugins
5) cp provisioner ^^ into ~/.terraform.d/plugins renaming to match the version ala: 
```
cp terraform-provisioner-ansible-darwin-amd64_v2.3.3 ~/.terraform.d/plugins/terraform-provisioner-ansible_v0.12.16
chmod +x ~/.terraform.d/plugins/terraform-provisioner-ansible_v0.12.16
```

Then terraform yerself a https://github.com/jeffbryner/urban-octo-couscous