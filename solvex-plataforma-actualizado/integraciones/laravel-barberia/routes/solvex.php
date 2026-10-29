<?php
/*
 * Pega estas líneas donde indica el LEEME.
 */

// routes/api.php  (las rutas de api.php no usan CSRF ni sesión)
use App\Http\Controllers\SolvexWebhookController;
use Illuminate\Support\Facades\Route;

Route::post('/solvex/webhook', SolvexWebhookController::class)
    ->middleware('throttle:120,1')
    ->name('solvex.webhook');

// routes/console.php
// use Illuminate\Support\Facades\Schedule;
// Schedule::command('solvex:sync')->everyFiveMinutes()->withoutOverlapping();
