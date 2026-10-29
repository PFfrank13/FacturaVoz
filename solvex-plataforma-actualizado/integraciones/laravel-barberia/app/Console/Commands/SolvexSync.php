<?php

namespace App\Console\Commands;

use App\Models\Business;
use App\Services\Solvex\SolvexHub;
use Illuminate\Console\Command;

/**
 * php artisan solvex:sync
 * Respaldo de los webhooks: trae el estado de todas las licencias cada 5 minutos.
 * Programado en routes/console.php:  Schedule::command('solvex:sync')->everyFiveMinutes()->withoutOverlapping();
 */
class SolvexSync extends Command
{
    protected $signature = 'solvex:sync';

    protected $description = 'Sincroniza las licencias de las barberías con Solvex Hub';

    public function handle(): int
    {
        if (! config('solvex.enabled', true)) {
            $this->warn('Solvex desactivado (SOLVEX_ENABLED=false).');

            return self::SUCCESS;
        }
        $n = SolvexHub::syncAll();
        if ($n < 0) {
            $this->error('No se pudo conectar con Solvex Hub. Se mantiene el último estado verificado.');

            return self::FAILURE;
        }
        SolvexHub::heartbeat(Business::query()->count());
        $this->info("Licencias actualizadas: {$n}");

        return self::SUCCESS;
    }
}
