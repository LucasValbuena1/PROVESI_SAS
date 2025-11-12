from django.shortcuts import render, redirect
from django.contrib.auth import logout as django_logout
from django.conf import settings
import urllib.parse

def home(request):
    return render(request, "home.html")

def logout_view(request):
    # Hacer logout en Django
    django_logout(request)
    
    # Construir la URL de logout de Auth0
    domain = settings.SOCIAL_AUTH_AUTH0_DOMAIN
    client_id = settings.SOCIAL_AUTH_AUTH0_KEY
    return_to = urllib.parse.quote_plus(request.build_absolute_uri('/'))
    
    logout_url = f'https://{domain}/v2/logout?client_id={client_id}&returnTo={return_to}'
    
    return redirect(logout_url)