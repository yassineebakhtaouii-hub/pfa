<?php
// =============================================================================
// index.php - PFA WebServer Homepage
// =============================================================================
session_start();
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>PFA - Plateforme de Securite</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: Arial, sans-serif; background: #f0f2f5; color: #333; }
        .container { max-width: 800px; margin: 50px auto; padding: 20px; }
        .card { background: white; border-radius: 8px; padding: 30px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #1a73e8; margin-bottom: 20px; }
        p { line-height: 1.6; margin-bottom: 15px; }
        .nav { list-style: none; margin: 20px 0; }
        .nav li { margin: 10px 0; }
        .nav a { display: block; padding: 12px; background: #e8f0fe; border-radius: 6px;
                 color: #1a73e8; text-decoration: none; font-weight: bold; }
        .nav a:hover { background: #d2e3fc; }
        .footer { margin-top: 30px; font-size: 12px; color: #666; text-align: center; }
    </style>
</head>
<body>
<div class="container">
    <div class="card">
        <h1>Plateforme de Securite Modulaire Virtualisee</h1>
        <p>Bienvenue sur la plateforme PFA. Ce serveur heberge des applications
        de demonstration pour les tests de securite.</p>
        <ul class="nav">
            <li><a href="login.php">Portail d'authentification</a></li>
            <li><a href="info.php">Information serveur</a></li>
        </ul>
        <div class="footer">
            PFA - Projet de Fin d'Annee &copy; 2026<br>
            ATTENTION: Ce serveur est vulnerable volontairement pour tests de penetration.
        </div>
    </div>
</div>
</body>
</html>
