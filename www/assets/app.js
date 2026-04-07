// PurchaseBridge SPA - Frontend Application
(function() {
    'use strict';

    // Estado de la aplicación
    let authToken = localStorage.getItem('authToken') || null;
    let currentUser = null;

    // Elementos del DOM
    const sections = {
        home: document.getElementById('home'),
        login: document.getElementById('login'),
        dashboard: document.getElementById('dashboard')
    };

    const authLinks = document.getElementById('auth-links');
    const loginLink = document.getElementById('login-link');
    const loginForm = document.getElementById('login-form');
    const loginError = document.getElementById('login-error');
    const testApiBtn = document.getElementById('test-api-btn');
    const apiResponse = document.getElementById('api-response');
    const logoutBtn = document.getElementById('logout-btn');

    // Función para mostrar una sección y ocultar las demás
    function showSection(sectionName) {
        Object.keys(sections).forEach(key => {
            if (sections[key]) {
                sections[key].style.display = key === sectionName ? 'block' : 'none';
            }
        });
    }

    // Actualizar UI según estado de autenticación
    function updateAuthUI() {
        if (authToken) {
            authLinks.innerHTML = '<span id="user-info">Usuario conectado</span> <button id="logout-btn-nav" style="margin-left: 10px;">Cerrar Sesión</button>';
            document.getElementById('logout-btn-nav').addEventListener('click', logout);
            
            // Si estamos en home, mostrar dashboard
            if (sections.home.style.display !== 'none') {
                showSection('dashboard');
            }
        } else {
            authLinks.innerHTML = '<a href="/login" id="login-link">Login</a>';
            showSection('home');
        }
    }

    // Navegación SPA
    function navigate(path) {
        const cleanPath = path.split('?')[0]; // Remover query params
        
        // Manejar rutas
        if (cleanPath === '/' || cleanPath === '') {
            showSection('home');
        } else if (cleanPath === '/login') {
            if (authToken) {
                // Si ya está logueado, ir al dashboard
                showSection('dashboard');
            } else {
                showSection('login');
            }
        } else if (cleanPath === '/dashboard') {
            if (authToken) {
                showSection('dashboard');
            } else {
                // Redirigir a login si no hay token
                window.history.pushState({}, '', '/login');
                showSection('login');
            }
        } else {
            // Para cualquier otra ruta, mostrar home (fallback SPA)
            showSection('home');
        }
    }

    // Manejar el botón atrás/adelante del navegador
    window.addEventListener('popstate', function(event) {
        navigate(window.location.pathname);
    });

    // Interceptación de clicks en enlaces para navegación SPA
    document.addEventListener('click', function(event) {
        if (event.target.tagName === 'A' && event.target.href.startsWith(window.location.origin)) {
            const path = event.target.getAttribute('href').replace(window.location.origin, '');
            // Solo interceptar si es una ruta SPA (no archivos estáticos)
            if (!path.includes('.') || path.endsWith('/')) {
                event.preventDefault();
                window.history.pushState({}, '', path);
                navigate(path);
            }
        }
    });
    // Manejar recarga de página (F5) - verificar sesión expirada
    window.addEventListener('beforeunload', function() {
      // Guardar el estado actual antes de recargar
      sessionStorage.setItem('lastPath', window.location.pathname);
    });

    // Al cargar la página, verificar si venimos de un refresh y validar sesión
    window.addEventListener('load', function() {
      const lastPath = sessionStorage.getItem('lastPath');
      if (lastPath && lastPath !== '/login' && lastPath !== '/') {
        // Si estábamos en una ruta protegida y hay refresh, verificar token
        if (!authToken) {
          // No hay token, redirigir a login sin mostrar error
          window.history.replaceState({}, '', '/login');
          showSection('login');
        }
      }
      sessionStorage.removeItem('lastPath');
    });

    // Login
    async function login(event) {
        event.preventDefault();
        
        const usuario = document.getElementById('usuario').value;
        const clave = document.getElementById('clave').value;

        try {
            const response = await fetch('/api/auth/login', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ usuario, clave })
            });

            const data = await response.json();

            if (response.ok && data.success !== false) {
                // Guardar token
                authToken = data.token || data.accessToken;
                if (authToken) {
                    localStorage.setItem('authToken', authToken);
                }
                
                loginError.style.display = 'none';
                
                // Redirigir al dashboard
                window.history.pushState({}, '', '/dashboard');
                updateAuthUI();
                showSection('dashboard');
            } else {
                loginError.textContent = data.message || 'Error en las credenciales';
                loginError.style.display = 'block';
            }
        } catch (error) {
            loginError.textContent = 'Error de conexión con el servidor';
            loginError.style.display = 'block';
            console.error('Login error:', error);
        }
    }

    // Logout
    function logout() {
        authToken = null;
        localStorage.removeItem('authToken');
        currentUser = null;
        
        window.history.pushState({}, '', '/');
        updateAuthUI();
        showSection('home');
    }

    // Test API Ping
    async function testApi() {
        try {
            const response = await fetch('/ping');
            const data = await response.json();
            apiResponse.textContent = JSON.stringify(data, null, 2);
        } catch (error) {
            apiResponse.textContent = 'Error: ' + error.message;
        }
    }


    // Verificar sesión expirada al hacer peticiones API
    async function fetchWithAuth(url, options = {}) {
        if (authToken) {
            options.headers = options.headers || {};
            options.headers['Authorization'] = 'Bearer ' + authToken;
        }

        const response = await fetch(url, options);

        // Si recibimos 401, la sesión expiró - redirigir sin mostrar error
        if (response.status === 401) {
            logout();
            // No mostrar alert, solo redirigir silenciosamente a login
            window.history.replaceState({}, '', '/login');
            showSection('login');
            throw new Error('Sesión expirada');
        }

        return response;
    }

    // Inicialización
    function init() {
        // Configurar event listeners
        if (loginForm) {
            loginForm.addEventListener('submit', login);
        }

        if (testApiBtn) {
            testApiBtn.addEventListener('click', testApi);
        }

        if (logoutBtn) {
            logoutBtn.addEventListener('click', logout);
        }

        // Restaurar estado de autenticación
        updateAuthUI();

        // Navegar a la ruta actual
        navigate(window.location.pathname);

        console.log('PurchaseBridge SPA initialized');
    }

    // Ejecutar cuando el DOM esté listo
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
