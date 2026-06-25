<?php
// =============================================================================
// login.php - DELIBERATELY VULNERABLE to SQL injection
// Vulnerability: String concatenation in SQL query (no prepared statements)
// CWE-89: Improper Neutralization of Special Elements used in SQL Command
// =============================================================================
session_start();

// Display error messages in HTML (information disclosure)
if (isset($_GET['error'])) {
    echo '<p style="color:red;text-align:center;">' . htmlspecialchars($_GET['error']) . '</p>';
}

// Connect to PostgreSQL - credentials exposed in source (CWE-798)
$conn = pg_connect("host=10.0.2.10 port=5432 dbname=pfadb user=pfa_user password=pfa_pass_2026");
if (!$conn) {
    die("Erreur de connexion a la base de donnees.");
}

$message = "";

if ($_SERVER["REQUEST_METHOD"] == "POST") {
    $username = $_POST["username"] ?? "";
    $password = $_POST["password"] ?? "";

    // VULNERABLE: Direct string interpolation in SQL query
    // Attack: ' OR 1=1 --  bypasses authentication
    $sql = "SELECT * FROM users WHERE username='$username' AND password='$password'";
    $result = pg_query($conn, $sql);

    if ($result && pg_num_rows($result) > 0) {
        $row = pg_fetch_assoc($result);
        $_SESSION["user"] = $row["username"];
        $_SESSION["role"] = $row["role"] ?? "user";
        $message = "Connexion reussie. Bienvenue " . htmlspecialchars($row["username"]);
    } else {
        $error_detail = $result ? "Identifiants invalides." : "Erreur SQL: " . pg_last_error($conn);
        $message = "Echec de connexion: " . $error_detail;
    }
}
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Authentification - PFA</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: Arial, sans-serif; background: #f0f2f5; display: flex;
               justify-content: center; align-items: center; height: 100vh; }
        .card { background: white; border-radius: 8px; padding: 40px; width: 400px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #1a73e8; margin-bottom: 25px; text-align: center; }
        label { display: block; margin-bottom: 5px; font-weight: bold; }
        input[type="text"], input[type="password"] { width: 100%; padding: 10px;
               margin-bottom: 20px; border: 1px solid #ddd; border-radius: 4px; }
        input[type="submit"] { width: 100%; padding: 12px; background: #1a73e8;
               color: white; border: none; border-radius: 4px; font-size: 16px; cursor: pointer; }
        .message { margin-top: 20px; padding: 10px; border-radius: 4px; text-align: center; }
        .success { background: #d4edda; color: #155724; }
        .error { background: #f8d7da; color: #721c24; }
    </style>
</head>
<body>
<div class="card">
    <h1>Authentification</h1>
    <form method="POST">
        <label for="username">Nom d'utilisateur</label>
        <input type="text" id="username" name="username" placeholder="Entrez votre nom d'utilisateur">
        <label for="password">Mot de passe</label>
        <input type="password" id="password" name="password" placeholder="Entrez votre mot de passe">
        <input type="submit" value="Se connecter">
    </form>
    <?php if ($message): ?>
        <div class="message <?php echo strpos($message, 'reussie') !== false ? 'success' : 'error'; ?>">
            <?php echo $message; ?>
        </div>
    <?php endif; ?>
    <p style="margin-top:20px;font-size:12px;color:#999;text-align:center;">
        Indice: L'authentification est vulnerable a l'injection SQL.
    </p>
</div>
</body>
</html>
