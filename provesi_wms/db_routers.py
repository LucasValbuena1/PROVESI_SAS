"""
Database Router para microservicios.

Dirige las consultas de cada app a su base de datos correspondiente:
- clients -> clients_db
- orders -> orders_db
- default -> default (auth, sessions, admin, etc.)
"""


class MicroserviceRouter:
    """
    Router que dirige las operaciones de base de datos
    a la base de datos correspondiente según la app.
    """
    
    # Mapeo de apps a bases de datos
    route_app_labels = {
        'clients': 'clients_db',
        'orders': 'orders_db',
    }

    def db_for_read(self, model, **hints):
        """
        Dirige las lecturas a la base de datos correspondiente.
        """
        app_label = model._meta.app_label
        if app_label in self.route_app_labels:
            return self.route_app_labels[app_label]
        return 'default'

    def db_for_write(self, model, **hints):
        """
        Dirige las escrituras a la base de datos correspondiente.
        """
        app_label = model._meta.app_label
        if app_label in self.route_app_labels:
            return self.route_app_labels[app_label]
        return 'default'

    def allow_relation(self, obj1, obj2, **hints):
        """
        Permite relaciones entre objetos de diferentes bases de datos.
        Esto es necesario para que Order pueda referenciar a Client
        aunque estén en bases de datos diferentes.
        """
        # Permitir relaciones entre clients y orders
        app_labels = {obj1._meta.app_label, obj2._meta.app_label}
        if app_labels.issubset({'clients', 'orders'}):
            return True
        # Permitir relaciones dentro de la misma base de datos
        if obj1._meta.app_label == obj2._meta.app_label:
            return True
        return None

    def allow_migrate(self, db, app_label, model_name=None, **hints):
        """
        Asegura que las migraciones se ejecuten en la base de datos correcta.
        """
        if app_label in self.route_app_labels:
            return db == self.route_app_labels[app_label]
        # Las apps del sistema (auth, admin, etc.) van a default
        return db == 'default'