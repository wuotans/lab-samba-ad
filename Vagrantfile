# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  
  # Configurações globais
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.box_check_update = false

  # Controlador de dominio samba AD primario
  config.vm.define "samba-dc1", primary: true do |dc|
    dc.vm.box = "generic/ubuntu2004"
    dc.vm.box_version = "4.2.16"
    dc.vm.hostname = "dc1.teste.com"
    dc.vm.network = "private_network",
      ip: "192.168.56.10",
      netmask: "255.255.255.0"
      virtualbox__intnet: "samba-lab"

    # Configurações de hardware
    dc.vm.provider "virtualbox" do |vb|
      vb.name = "Samba-DC1"
      vb.memory = 4096
      vb.cpus = 2
      vb.customize [
        "modifyvm", :id,
        "--nicpromisc2", "allow-all",
        "--audio", "none",
        "--clipboard", "bidirectional",
        "--draganddrop", "bidirectional"
      ]
    end
    
    # Provisionamento
    dc.vm.provision "shell",
      path: "scripts/samba-ad-setup.sh",
      args: ["dc1","192.168.56.10", "primary"]
    
    dc.vm.provision "shell",
      path: "scripts/configure-dns.sh",
      run: "always"
    
    dc.vm.provision "shell",
      path: "scripts/setup-ldaps-cert.sh"
  end

  # Controlador de dominio samba AD secundario
  config.vm.define "samba-dc2" do |dc|
    dc.vm.box = "generic/ubuntu2004"