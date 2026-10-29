<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Estado de licencia de cada barbería, tal como lo informa Solvex Hub.
 * Se guarda el último token firmado para poder re-verificarlo y para decidir sin conexión
 * (el token trae su propia fecha de corte).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('businesses', function (Blueprint $table) {
            $table->string('license_code', 20)->nullable()->after('plan_code');        // LIC-00012
            $table->string('license_status', 20)->nullable()->after('license_code');   // pendiente|prueba|activa|gracia|suspendida|cancelada
            $table->string('license_mode', 12)->nullable()->after('license_status');   // full|warning|restricted|blocked
            $table->dateTime('license_period_end')->nullable();                         // UTC: pagado hasta
            $table->dateTime('license_cut_at')->nullable();                             // UTC: corte automático si no paga
            $table->text('license_message')->nullable();
            $table->string('license_pay_url', 300)->nullable();
            $table->json('license_features')->nullable();                               // límites del plan (max_branches...)
            $table->text('license_token')->nullable();                                  // último token firmado
            $table->unsignedBigInteger('license_token_iat')->nullable();                // para ignorar avisos más viejos
            $table->dateTime('license_token_exp')->nullable();
            $table->dateTime('license_checked_at')->nullable();

            // Índice: el middleware y las tareas buscan barberías por modo de licencia.
            $table->index('license_mode');
        });
    }

    public function down(): void
    {
        Schema::table('businesses', function (Blueprint $table) {
            $table->dropIndex(['license_mode']);
            $table->dropColumn(['license_code', 'license_status', 'license_mode', 'license_period_end', 'license_cut_at', 'license_message',
                'license_pay_url', 'license_features', 'license_token', 'license_token_iat', 'license_token_exp', 'license_checked_at']);
        });
    }
};
