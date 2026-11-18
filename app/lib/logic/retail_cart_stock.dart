import '../models.dart';

/// Mensaje temprano para la caja; NO sustituye al bloqueo atómico en SQL.
/// Sin control de stock (NULL), el POS no limita la cantidad.
bool exceedsKnownRetailStock(Product product, double inCart, double delta) =>
    delta > 0 &&
    product.tracksStock &&
    inCart + delta > product.stock! + 0.0000001;
