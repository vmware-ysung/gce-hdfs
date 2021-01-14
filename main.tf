provider "google" {
  credentials = file(var.gcp_profile.credentials)
  project = var.gcp_profile.project
  region = var.gcp_profile.region
  zone = var.gcp_profile.zone
}

data "external" "myipaddr" {
  program = ["sh", "-c", "curl -s 'https://api.ipify.org?format=json'"]
}

resource "google_compute_firewall" "hdsf_allow_internal" {
  name = "hdfs-allow-internal"
  network = google_compute_network.hdfs_network.name
  allow {
    protocol = "sctp"
  }
  allow {
    protocol = "ipip"
  }
  allow {
    protocol = "tcp"
  }
    allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = [var.vpc_subnet_cidr]
}

resource "google_compute_firewall" "hdfs_allow_external" {
  name = "hdfs-allow-external"
  network = google_compute_network.hdfs_network.name
  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports = [22]
  }
  source_ranges = [lookup(data.external.myipaddr.result,"ip")]
}

resource "google_compute_network" "hdfs_network" {
  name = "hdfs-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "hdfs_subnet" {
  name = "hdfs-subnet"
  ip_cidr_range = var.vpc_subnet_cidr
  network = google_compute_network.hdfs_network.name
}

resource "google_compute_instance" "myipa" {
  name    = "myipa"
  machine_type  = var.gce_vm.instance_type
  hostname = "myipa.${var.gcp_dns_name}"
  metadata  = {
    ssh-keys = "${var.gce_vm.ssh_user}: ${file(var.gce_vm.ssh_pub)}"
  }
  boot_disk {
    auto_delete   = true
    initialize_params {
      size  = var.gce_vm.boot_disk_size
      image = "${var.gce_vm.os_project}/${var.gce_vm.os_family}"
    }
  }
  network_interface {
    subnetwork  = google_compute_subnetwork.hdfs_subnet.self_link
    network_ip  = cidrhost(var.vpc_subnet_cidr, 4)
    access_config {
    }
  }
}

resource "google_compute_instance" "master" {
  count = var.hdfs_master_count
  name    = "master${count.index+1}"
  machine_type  = var.gce_vm.instance_type
  hostname = "master${count.index+1}.${var.gcp_dns_name}"
  metadata  = {
    ssh-keys = "${var.gce_vm.ssh_user}: ${file(var.gce_vm.ssh_pub)}"
  }
  boot_disk {
    auto_delete   = true
    initialize_params {
      size  = var.gce_vm.boot_disk_size
      image = "${var.gce_vm.os_project}/${var.gce_vm.os_family}"
    }
  }
  network_interface {
    subnetwork  = google_compute_subnetwork.hdfs_subnet.self_link
    network_ip  = cidrhost(var.vpc_subnet_cidr, count.index+10)
    access_config {
    }
  }
}

resource "google_compute_instance" "worker" {
  count = var.hdfs_worker_count
  name    = "worker${count.index+1}"
  machine_type  = var.gce_vm.instance_type
  hostname = "worker${count.index+1}.${var.gcp_dns_name}"
  metadata  = {
    ssh-keys = "${var.gce_vm.ssh_user}: ${file(var.gce_vm.ssh_pub)}"
  }
  boot_disk {
    auto_delete   = true
    initialize_params {
      size  = var.gce_vm.boot_disk_size
      image = "${var.gce_vm.os_project}/${var.gce_vm.os_family}"
    }
  }
  network_interface {
    subnetwork  = google_compute_subnetwork.hdfs_subnet.self_link
    network_ip  = cidrhost(var.vpc_subnet_cidr, count.index+20)
    access_config {
    }
  }
}

resource "local_file" "ansible_host" {
 content = templatefile("templates/hosts.tpl",
     {
     ipa = google_compute_instance.myipa.*.network_interface.0.access_config.0.nat_ip
     master = google_compute_instance.master.*.network_interface.0.access_config.0.nat_ip
     worker = google_compute_instance.worker.*.network_interface.0.access_config.0.nat_ip
     }
  )
 filename = "${path.module}/hosts"
}

resource "null_resource" "ansible_playbook_os" {
  depends_on = [
  local_file.ansible_host,
  ]
  provisioner "local-exec" {
    command = "ansible-playbook os/main.yaml"
  }
}

resource "null_resource" "ansible_playbook_hdfs" {
  depends_on = [
  null_resource.ansible_playbook_os,
  ]
  provisioner "local-exec" {
    command = "ansible-playbook hdfs/main.yaml"
  }
}
