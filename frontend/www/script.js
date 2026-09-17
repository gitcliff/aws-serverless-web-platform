// ── Cognito config ────────────────────────────────────────────────────────────
// After `terraform apply`, fill these in from:
//   terraform output -raw cognito_app_client_id
//   terraform output -raw cognito_hosted_ui_domain
const COGNITO_CLIENT_ID = '5iifcr06ltd8oub6m8ro8641j9';
const COGNITO_DOMAIN    = 'https://dev-cliffworld.auth.us-east-1.amazoncognito.com';
const COGNITO_REDIRECT_URI = window.location.origin + '/callback';

// ── PKCE helpers ──────────────────────────────────────────────────────────────
function generateVerifier() {
    const array = new Uint8Array(32);
    crypto.getRandomValues(array);
    return btoa(String.fromCharCode(...array))
        .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

async function generateChallenge(verifier) {
    const data = new TextEncoder().encode(verifier);
    const digest = await crypto.subtle.digest('SHA-256', data);
    return btoa(String.fromCharCode(...new Uint8Array(digest)))
        .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

// ── Token management ──────────────────────────────────────────────────────────
function getAccessToken() {
    return sessionStorage.getItem('access_token');
}

function storeTokens(accessToken, idToken) {
    sessionStorage.setItem('access_token', accessToken);
    sessionStorage.setItem('id_token', idToken);
}

function clearTokens() {
    sessionStorage.removeItem('access_token');
    sessionStorage.removeItem('id_token');
    sessionStorage.removeItem('pkce_verifier');
}

function isTokenValid(token) {
    if (!token) return false;
    try {
        const payload = JSON.parse(atob(token.split('.')[1]));
        return payload.exp * 1000 > Date.now();
    } catch {
        return false;
    }
}

// ── Auth actions ──────────────────────────────────────────────────────────────
// Precomputed PKCE pair — generated once at page load inside the async
// DOMContentLoaded handler so login() stays synchronous and can never
// silently fail due to an unhandled async rejection in a click handler.
let _pkceVerifier   = null;
let _pkceChallenge  = null;

async function initPkce() {
    _pkceVerifier  = generateVerifier();
    _pkceChallenge = await generateChallenge(_pkceVerifier);
}

function login() {
    if (!_pkceChallenge) {
        console.error('PKCE not ready — crypto.subtle may be unavailable');
        return;
    }
    sessionStorage.setItem('pkce_verifier', _pkceVerifier);

    const params = new URLSearchParams({
        response_type:         'code',
        client_id:             COGNITO_CLIENT_ID,
        redirect_uri:          COGNITO_REDIRECT_URI,
        scope:                 'openid email profile',
        code_challenge:        _pkceChallenge,
        code_challenge_method: 'S256',
    });
    window.location.href = `${COGNITO_DOMAIN}/oauth2/authorize?${params}`;
}

async function handleCallback() {
    const params = new URLSearchParams(window.location.search);
    const code = params.get('code');
    if (!code) return false;

    // Remove ?code= from the URL so refreshing the page does not re-submit
    window.history.replaceState({}, document.title, window.location.pathname);

    const verifier = sessionStorage.getItem('pkce_verifier');
    if (!verifier) return false;

    const body = new URLSearchParams({
        grant_type:    'authorization_code',
        client_id:     COGNITO_CLIENT_ID,
        redirect_uri:  COGNITO_REDIRECT_URI,
        code,
        code_verifier: verifier,
    });

    try {
        const res = await fetch(`${COGNITO_DOMAIN}/oauth2/token`, {
            method:  'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body:    body.toString(),
        });
        if (!res.ok) return false;
        const tokens = await res.json();
        storeTokens(tokens.access_token, tokens.id_token);
        sessionStorage.removeItem('pkce_verifier');
        return true;
    } catch {
        return false;
    }
}

function logout() {
    clearTokens();
    const params = new URLSearchParams({
        client_id:  COGNITO_CLIENT_ID,
        logout_uri: window.location.origin,
    });
    window.location.href = `${COGNITO_DOMAIN}/logout?${params}`;
}

// ── Dashboard ─────────────────────────────────────────────────────────────────
async function fetchDashboard() {
    const token = getAccessToken();
    if (!isTokenValid(token)) {
        updateAuthUI(false);
        return;
    }

    try {
        const res = await fetch('/api/dashboard', {
            headers: { 'Authorization': `Bearer ${token}` },
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        document.getElementById('dashboard-email').textContent   = data.email;
        document.getElementById('dashboard-message').textContent = data.message;
    } catch (err) {
        console.error('Dashboard fetch failed:', err);
    }
}

// ── Auth UI state ─────────────────────────────────────────────────────────────
function updateAuthUI(isLoggedIn) {
    document.getElementById('login-btn').style.display  = isLoggedIn ? 'none'         : 'inline-block';
    document.getElementById('logout-btn').style.display = isLoggedIn ? 'inline-block' : 'none';
    const dashSection = document.getElementById('dashboard-section');
    if (dashSection) dashSection.style.display = isLoggedIn ? 'block' : 'none';
}

// ── Visitor counter ───────────────────────────────────────────────────────────
const counterButton = document.getElementById('counterButton');
const counterSpan   = document.getElementById('counter');
const statusElement = document.getElementById('status');

function updateStatus(text, ok) {
    statusElement.textContent = text;
    const dot = document.querySelector('.status-dot');
    if (dot) dot.style.background = ok ? '#4ade80' : '#f87171';
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

// Theme toggle
const colorButton = document.getElementById('colorButton');
let isDarkTheme = false;

colorButton.addEventListener('click', function() {
    isDarkTheme = !isDarkTheme;
    document.body.classList.toggle('dark-theme');
    colorButton.textContent = isDarkTheme ? 'Light Theme' : 'Dark Theme';
    localStorage.setItem('darkTheme', isDarkTheme);
});

// Each click increments the server-side counter (Lambda → DynamoDB ADD)
counterButton.addEventListener('click', function() {
    counterSpan.textContent = '...';
    fetchVisitorCount();
    counterButton.style.transform = 'scale(0.95)';
    setTimeout(() => { counterButton.style.transform = 'scale(1)'; }, 100);
});

// Auth button wiring
document.getElementById('login-btn').addEventListener('click', login);
document.getElementById('logout-btn').addEventListener('click', logout);

// Keyboard shortcuts
document.addEventListener('keydown', function(e) {
    if (e.code === 'Space') {
        e.preventDefault();
        counterButton.click();
    } else if (e.key === 't' || e.key === 'T') {
        colorButton.click();
    }
});

// Animation on load
function animateOnLoad() {
    const cards = document.querySelectorAll('.feature-card');
    cards.forEach((card, index) => {
        card.style.opacity   = '0';
        card.style.transform = 'translateY(20px)';
        setTimeout(() => {
            card.style.transition = 'all 0.6s ease';
            card.style.opacity    = '1';
            card.style.transform  = 'translateY(0)';
        }, index * 150);
    });
}

document.addEventListener('DOMContentLoaded', async function() {
    // Pre-generate PKCE pair so login() is a plain synchronous redirect
    await initPkce();

    fetchVisitorCount();

    const savedTheme = localStorage.getItem('darkTheme');
    if (savedTheme === 'true') {
        isDarkTheme = true;
        document.body.classList.add('dark-theme');
        colorButton.textContent = 'Light Theme';
    }

    animateOnLoad();

    // Handle Cognito callback redirect (?code=...)
    const callbackHandled = await handleCallback();

    // Restore auth state
    const loggedIn = callbackHandled || isTokenValid(getAccessToken());
    updateAuthUI(loggedIn);
    if (loggedIn) fetchDashboard();

    // Hover effects for feature cards
    document.querySelectorAll('.feature-card').forEach(card => {
        card.addEventListener('mouseenter', function() {
            this.style.transform = 'translateY(-10px) scale(1.02)';
        });
        card.addEventListener('mouseleave', function() {
            this.style.transform = 'translateY(0) scale(1)';
        });
    });
});
