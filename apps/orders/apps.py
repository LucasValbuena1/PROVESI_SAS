from django.apps import AppConfig

class OrdersConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.orders"
    label = "orders"

    def ready(self):
        """
        (Opcional) Registrar señales para invalidación de caché cuando cambie Order.
        Si aún no tienes apps/orders/signals.py puedes dejarlo así; el try/except evita errores.
        """
        try:
            from . import signals  # noqa: F401
        except Exception:
            pass
