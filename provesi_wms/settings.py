from pathlib import Path
import os

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent


# Quick-start development settings - unsuitable for production
SECRET_KEY = 'django-insecure-*5p2t&g88*0x1vobm^1d(fw3*0-s(h2v(i5#$)!qy7s3)+fn1d'

DEBUG = True

ALLOWED_HOSTS = ["127.0.0.1", "localhost"]


# Application definition

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'apps.security',  # Microservicio de seguridad
    'apps.clients',   # Microservicio de clientes
    'apps.orders',    # Microservicio de órdenes
    'apps.home',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    # Middleware de seguridad para microservicios
    'apps.security.middleware.MicroserviceSecurityMiddleware',
]

ROOT_URLCONF = 'provesi_wms.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'provesi_wms.wsgi.application'


# Database Configuration - Multiple Databases for Microservices

DATABASES = {
    # Base de datos por defecto (para auth, sessions, admin, etc.)
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": "provesi_wms",
        "USER": "provesi",
        "PASSWORD": "1234",
        "HOST": "127.0.0.1",
        "PORT": "5432",
        "CONN_MAX_AGE": 60,
    },
    # Base de datos para el microservicio de Clientes
    "clients_db": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": "provesi_clients",
        "USER": "provesi",
        "PASSWORD": "1234",
        "HOST": "127.0.0.1",
        "PORT": "5432",
        "CONN_MAX_AGE": 60,
    },
    # Base de datos para el microservicio de Órdenes
    "orders_db": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": "provesi_orders",
        "USER": "provesi",
        "PASSWORD": "1234",
        "HOST": "127.0.0.1",
        "PORT": "5432",
        "CONN_MAX_AGE": 60,
    },
}

# Database Routers
DATABASE_ROUTERS = ['provesi_wms.db_routers.MicroserviceRouter']


# ===========================================
# SEGURIDAD - Las claves están predefinidas en crypto_service.py
# No requiere configuración manual para desarrollo
# ===========================================

# Token de servicio para autenticación entre microservicios
MICROSERVICE_SERVICE_TOKEN = 'provesi_service_token_2024'


# ===========================================
# LOGGING CONFIGURATION
# ===========================================

# Crear directorio de logs si no existe
LOGS_DIR = BASE_DIR / 'logs'
LOGS_DIR.mkdir(exist_ok=True)

LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '{levelname} {asctime} {module} {message}',
            'style': '{',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'verbose',
        },
        'security_file': {
            'class': 'logging.FileHandler',
            'filename': LOGS_DIR / 'security.log',
            'formatter': 'verbose',
        },
    },
    'loggers': {
        'apps.security': {
            'handlers': ['console', 'security_file'],
            'level': 'INFO',
            'propagate': False,
        },
        'apps.orders': {
            'handlers': ['console'],
            'level': 'INFO',
        },
        'apps.clients': {
            'handlers': ['console'],
            'level': 'INFO',
        },
    },
}


# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]


# Internationalization
LANGUAGE_CODE = 'es-co'
TIME_ZONE = 'America/Bogota'
USE_I18N = True
USE_TZ = True


# Static files
STATIC_URL = 'static/'

# Default primary key field type
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'