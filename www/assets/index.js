// PurchaseBridge - Aplicación principal

document.addEventListener('DOMContentLoaded', function() {
    console.log('PurchaseBridge inicializado');
    
    // Navegación simple
    const navLinks = document.querySelectorAll('.nav-link');
    navLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            navLinks.forEach(l => l.classList.remove('active'));
            this.classList.add('active');
        });
    });
});
