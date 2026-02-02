# Vagrantfile para estudo de migração AD DS → Samba AD
Vagrant.configure("2") do |config|
  
  # =============================================
  # FASE 1: AMBIENTE AD WINDOWS ORIGINAL (Fonte)
  # =============================================
  
  # Controlador de Domínio Windows Server 2022
  config.vm.define "windows-dc", primary: true do |dc|
    dc.vm.box = "gusztavvargadr/windows-server"
    dc.vm.box_version = "2601.0.0"
    dc.vm.hostname = "dc-windows.almt.local"
    dc.vm.network "private_network", 
      ip: "192.168.100.10",
      netmask: "255.255.255.0",
      virtualbox__intnet: "migration-lab"
    
    dc.vm.provider "virtualbox" do |vb|
      vb.name = "Windows-AD-DC"
      vb.memory = 4096
      vb.cpus = 2
      vb.gui = true
    end
    
    # Instalar e configurar AD DS
    dc.vm.provision "shell",
      inline: "powershell -ExecutionPolicy Bypass -File C:/vagrant/windows-ad/scripts/windows-ad-setup.ps1",
      run: "once"
    
    # Configurar suas GPOs específicas
    dc.vm.provision "shell",
      inline: "powershell -ExecutionPolicy Bypass -File C:/vagrant/windows-ad/scripts/setup-gpos.ps1",
      run: "once"
  end
  
  # Estação Windows 10 Pro (cliente do domínio Windows)
  config.vm.define "win10-client" do |win|
    win.vm.box = "gusztavvargadr/windows-10"
    win.vm.box_version = "22.12.1"
    win.vm.hostname = "win10-client01"
    win.vm.network "private_network",
      ip: "192.168.100.20",
      netmask: "255.255.255.0",
      virtualbox__intnet: "migration-lab"
    
    win.vm.provider "virtualbox" do |vb|
      vb.name = "Windows10-Client-AD"
      vb.memory = 4096
      vb.cpus = 2
      vb.gui = true
    end
    
    # Ingressar no domínio Windows AD
    win.vm.provision "shell",
      inline: "powershell -ExecutionPolicy Bypass -File C:/vagrant/windows-ad/scripts/join-windows-domain.ps1",
      run: "once"
  end
  
  # =============================================
  # FASE 2: AMBIENTE SAMBA AD (Destino)
  # =============================================
  
  # Controlador de Domínio Samba AD (Linux)
  config.vm.define "samba-dc" do |samba|
    samba.vm.box = "generic/ubuntu2204"
    samba.vm.box_version = "4.2.16"
    samba.vm.hostname = "dc-samba.almt.local"
    samba.vm.network "private_network",
      ip: "192.168.100.100",
      netmask: "255.255.255.0",
      virtualbox__intnet: "migration-lab"
    
    samba.vm.provider "virtualbox" do |vb|
      vb.name = "Samba-AD-DC"
      vb.memory = 2048
      vb.cpus = 2
    end
    
    # Configurar Samba AD (SÓ DEPOIS do Windows AD estar pronto)
    samba.vm.provision "shell",
      path: "samba-ad/scripts/samba-ad-setup.sh",
      run: "once"
  end
  
  # Estação Linux para testes de integração
  config.vm.define "linux-client" do |linux|
    linux.vm.box = "generic/ubuntu2204"
    linux.vm.hostname = "client-linux.almt.local"
    linux.vm.network "private_network",
      ip: "192.168.100.150",
      netmask: "255.255.255.0",
      virtualbox__intnet: "migration-lab"
    
    linux.vm.provider "virtualbox" do |vb|
      vb.name = "Linux-Client-Test"
      vb.memory = 1024
      vb.cpus = 1
    end
  end
  
  # =============================================
  # FASE 3: SERVIDOR DE APLICAÇÕES
  # =============================================
  
  # Servidor Linux com aplicações (Nextcloud, GLPI, Moodle)
  config.vm.define "apps-server" do |apps|
    apps.vm.box = "generic/ubuntu2204"
    apps.vm.hostname = "apps.almt.local"
    apps.vm.network "private_network",
      ip: "192.168.100.200",
      netmask: "255.255.255.0",
      virtualbox__intnet: "migration-lab"
    
    apps.vm.provider "virtualbox" do |vb|
      vb.name = "Linux-Apps-Server"
      vb.memory = 3072
      vb.cpus = 2
    end
    
    # Instalar aplicações que usam AD
    apps.vm.provision "shell",
      path: "applications/setup-nextcloud.sh",
      run: "once"
    
    apps.vm.provision "shell",
      path: "applications/setup-glpi.sh",
      run: "once"
  end
end