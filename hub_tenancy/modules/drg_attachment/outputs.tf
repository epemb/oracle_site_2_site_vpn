output "id" {
  description = "Map of DRG Attachment IDs keyed by display name"
  value = { for k, drg_attachment in oci_core_drg_attachment.this : k => drg_attachment.id }
}