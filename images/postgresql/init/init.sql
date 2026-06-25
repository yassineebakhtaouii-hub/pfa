-- =============================================================================
-- init.sql - PostgreSQL Database Initialization
-- =============================================================================
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(100) NOT NULL,
    role VARCHAR(20) DEFAULT 'user',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO users (username, password, role) VALUES
    ('admin',    'admin123',   'administrator'),
    ('vulnuser', 'vulnpass123','user'),
    ('operator', 'password123','operator'),
    ('dev',      'devpass456', 'developer');
CREATE TABLE articles (
    id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    content TEXT,
    author_id INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO articles (title, content, author_id) VALUES
    ('Bienvenue sur la plateforme PFA',
     'Ceci est la plateforme de securite modulaire virtualisee. Utilisez les identifiants fournis.', 1),
    ('Architecture reseau',
     'DMZ: 10.0.1.0/24, LAN: 10.0.2.0/24, Monitoring: 10.0.3.0/24', 1),
    ('Notes de securite',
     'Verifier les journaux Suricata et Wazuh regulierement.', 2);
