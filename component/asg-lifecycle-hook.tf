resource "aws_autoscaling_lifecycle_hook" "app_launch" {
  count = var.enable_app_stack ? 1 : 0

  name                   = var.app_lifecycle_hook_name
  autoscaling_group_name = aws_autoscaling_group.app[0].name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
  heartbeat_timeout      = 300
  default_result         = "CONTINUE"

  # grace period와 중복되더라도 lifecycle hook을 우선 신뢰하도록 지연
  # 기대 효과: capacity 0 -> 1 상황에서도 안정적으로 target 등록
}
