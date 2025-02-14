# DYNAMIC "schedule": only create if the user provides
  # start_date_time or any expiration fields.
  dynamic "schedule" {
    for_each = (
      local.a.pim_start_date_time != null
      || local.a.pim_expiration_days  != null
      || local.a.pim_expiration_hours != null
      || local.a.pim_end_date_time    != null
    )
    ? [1] : []

    content {
      # If user provided a start_date_time, set it; else it will be null
      start_date_time = local.a.pim_start_date_time

      # DYNAMIC "expiration": only create if at least one expiration field is set
      dynamic "expiration" {
        for_each = (
          local.a.pim_expiration_days  != null
          || local.a.pim_expiration_hours != null
          || local.a.pim_end_date_time    != null
        )
        ? [1] : []

        content {
          duration_days  = local.a.pim_expiration_days
          duration_hours = local.a.pim_expiration_hours
          end_date_time  = local.a.pim_end_date_time
        }
      }
    }
