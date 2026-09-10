// Visitor counter — calls the real backend API
const counterButton = document.getElementById('counterButton');
const counterSpan = document.getElementById('counter');
const statusElement = document.getElementById('status');

function updateStatus(text, ok) {
    statusElement.textContent = text;
    const dot = document.querySelector('.status-dot');
    if (dot) {
        dot.style.background = ok ? '#4ade80' : '#f87171';
    }
}

async function fetchVisitorCount() {
    try {
        const res = await fetch('/api/visitor');
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        counterSpan.textContent = data.visitor_count;
        updateStatus('Connected', true);
    } catch (err) {
        counterSpan.textContent = 'unavailable';
        updateStatus('Error', false);
        console.error('Failed to fetch visitor count:', err);
    }
}

// Fetch count on page load
document.addEventListener('DOMContentLoaded', function() {
    fetchVisitorCount();

    // Load saved theme preference
    const savedTheme = localStorage.getItem('darkTheme');
    if (savedTheme === 'true') {
        isDarkTheme = true;
        document.body.classList.add('dark-theme');
        colorButton.textContent = 'Light Theme';
    }

    animateOnLoad();
});

// Each click increments the server-side counter
counterButton.addEventListener('click', function() {
    counterSpan.textContent = '...';
    fetchVisitorCount();

    counterButton.style.transform = 'scale(0.95)';
    setTimeout(() => {
        counterButton.style.transform = 'scale(1)';
    }, 100);
});

// Theme toggle
const colorButton = document.getElementById('colorButton');
let isDarkTheme = false;

colorButton.addEventListener('click', function() {
    isDarkTheme = !isDarkTheme;
    document.body.classList.toggle('dark-theme');
    colorButton.textContent = isDarkTheme ? 'Light Theme' : 'Dark Theme';
    localStorage.setItem('darkTheme', isDarkTheme);
});

// Animation on page load
function animateOnLoad() {
    const cards = document.querySelectorAll('.feature-card');
    cards.forEach((card, index) => {
        card.style.opacity = '0';
        card.style.transform = 'translateY(20px)';
        setTimeout(() => {
            card.style.transition = 'all 0.6s ease';
            card.style.opacity = '1';
            card.style.transform = 'translateY(0)';
        }, index * 200);
    });
}

// Hover effects for feature cards
document.addEventListener('DOMContentLoaded', function() {
    const featureCards = document.querySelectorAll('.feature-card');
    featureCards.forEach(card => {
        card.addEventListener('mouseenter', function() {
            this.style.transform = 'translateY(-10px) scale(1.02)';
        });
        card.addEventListener('mouseleave', function() {
            this.style.transform = 'translateY(0) scale(1)';
        });
    });
});

// Keyboard navigation
document.addEventListener('keydown', function(e) {
    if (e.code === 'Space') {
        e.preventDefault();
        counterButton.click();
    } else if (e.key === 't' || e.key === 'T') {
        colorButton.click();
    }
});
