resource "null_resource" "create_gitignore" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = templatefile("${path.module}/templates/gitignore.tftpl", {
      gitgnore = "${path.root}/.gitignore"
    })
  }
}