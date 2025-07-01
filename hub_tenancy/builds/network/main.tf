data "hcp_vault_secrets_app" "network_secrets"{
    app_name = "oracle-tenancy-secrets"
}

data "oci_core_instances" "libreswan" {
    compartment_id = data.hcp_vault_secrets_app.network_secrets.secrets["spoke_main_compartment_id"]
    display_name = "libreswan"
}

data "oci_core_vnic_attachments" "libreswan_attachment" {
    compartment_id = data.hcp_vault_secrets_app.network_secrets.secrets["spoke_main_compartment_id"]
    instance_id = oci_core_instance.libreswan.id
}

data "oci_core_vnic" "libreswan_vnic" {
    vnic_id = oci_core_vnic_attachments.libreswan_attachment[0].vnic_id
}

resource "oci_core_drg" "hub_drg" {    
    compartment_id = data.hcp_vault_secrets_app.network_secrets.secrets["main_compartment_id"]
    display_name = "hub-drg"
}


module "drg_attachment" {
source = "../../drg_attachment"
    drg_attachment_info = [{
        drg_id = oci_core_drg.hub_drg.id
        display_name = "priv-drg-attachment"
        drg_route_table_id = oci_core_drg_route_table.priv_drg_rt.id
        id = module.vcn.vcn_id
        type = "VCN"
        route_table_id = null
    }]
}

resource "oci_core_drg_route_table" "priv_drg_rt" {
    drg_id = oci_core_drg.test_drg.id
    display_name = "priv-drg-rt"
    import_drg_route_distribution_id = oci_core_drg_route_distribution.priv_rd.id
    is_ecmp_enabled = false
}

resource "oci_core_drg_route_distribution" "priv_rd" {
    distribution_type = "IMPORT"
    drg_id = oci_core_drg.hub_drg.id
    display_name = "priv-import-rd"
}

resource "oci_core_drg_route_distribution_statement" "priv_rd_statements" {
    drg_route_distribution_id = oci_core_drg_route_distribution.priv_import_rd.id
    action = "ACCEPT"
    
    match_criteria {
        match_type = "DRG_ATTACHMENT_TYPE"
        attachment_type = "IPSEC_TUNNEL"
        drg_attachment_id = oci_core_drg_attachment.test_drg_attachment.id
    }
    priority = 10

}

module "vcn" {
    source = "../../modules/vcn"

    vcn_info = [
        {
        compartment_id  = data.hcp_vault_secrets_app.network_secrets.secrets["main_compartment_id"]
        cidr_block      = var.vcn_cidr_block
        display_name    = "spoke-vcn-ashburn"
    }
    ]
}

module "priv_subnets" {
    source = "../../modules/subnet"
    subnet_info = local.priv_subnets

}

resource "oci_core_route_table" "priv_subnet_rt" {
    compartment_id = data.hcp_vault_secrets_app.network_secrets.secrets["main_compartment_id"]
    vcn_id = module.vcn.vcn_id
    display_name = "Default Route Table for pub-subnet"

    route_rules {
        network_entity_id = module.igw.id["spoke-igw"]
        description = "Forwards packets in pub subnet to IGW."
        destination = "0.0.0.0/0"
        destination_type = "CIDR_BLOCK"
    }
}


resource "oci_core_cpe" "spoke_cpe" {
    count = local.spoke_cpe_check

    compartment_id = data.hcp_vault_secrets_app.network_secrets.secrets["main_compartment_id"]
    ip_address = data.oci_core_vnic.libreswan_vnic.private_ip_address ? "value" : "value2"
    display_name = "spoke-cpe"
}



resource "oci_core_ipsec" "hub_ipsec_connection" {
    compartment_id = data.hcp_vault_secrets_app.network_secrets.secrets["main_compartment_id"]
    cpe_id = oci_core_cpe.spoke_cpe.id
    drg_id = oci_core_drg.hub_drg
    static_routes = []
    display_name = "hub-ipsec-1"
}

data "oci_core_ipsec_connection_tunnels" "ipsec_tunnels" {
    ipsec_id = oci_core_ipsec.hub_ipsec_connection.id
}

resource "oci_core_ipsec_connection_tunnel_management" "hub_ipsec_tunnel_mgmt" {
    ipsec_id = oci_core_ipsec.hub_ipsec_connection.id
    tunnel_id = data.oci_core_ipsec_connection_tunnels.ipsec_tunnels.ip_sec_connection_tunnels[0].id
    routing = "BGP"
    ike_version = "V2"

    bgp_session_info {
        customer_bgp_asn = var.ip_sec_connection_tunnel_management_bgp_session_info_customer_bgp_asn
        customer_interface_ip = var.ip_sec_connection_tunnel_management_bgp_session_info_customer_interface_ip
        oracle_interface_ip = var.ip_sec_connection_tunnel_management_bgp_session_info_oracle_interface_ip
    }

    encryption_domain_config {
        cpe_traffic_selector = "172.16.1.0/24"
        oracle_traffic_selector = "10.0.1.0/24"
    }
}