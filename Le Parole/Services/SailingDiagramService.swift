import Foundation

public struct WordDiagram: Identifiable, Sendable, Equatable {
    public let id: String
    public let promptImageName: String
    public let revealedImageName: String
    public let title: String
    public let plateName: String
    public let plateTitle: String
    public let caption: String?
    public let hasMatchingFullPlate: Bool

    /// Some source tables are represented only by a focused crop. Never expand
    /// those terms into a different, merely related boat plate.
    public var expandedImageName: String {
        hasMatchingFullPlate ? plateName : revealedImageName
    }

    public var expandedTitle: String {
        hasMatchingFullPlate ? plateTitle : title
    }

    public init(
        id: String,
        promptImageName: String,
        revealedImageName: String,
        title: String,
        plateName: String,
        plateTitle: String,
        caption: String?,
        hasMatchingFullPlate: Bool
    ) {
        self.id = id
        self.promptImageName = promptImageName
        self.revealedImageName = revealedImageName
        self.title = title
        self.plateName = plateName
        self.plateTitle = plateTitle
        self.caption = caption
        self.hasMatchingFullPlate = hasMatchingFullPlate
    }
}

public enum SailingDiagramService {
    private static let diagrams: [String: WordDiagram] = {
        var dict: [String: WordDiagram] = [:]

        func add(
            keys: [String],
            id: String,
            prompt: String,
            revealed: String,
            title: String,
            plate: String,
            plateTitle: String,
            caption: String?
        ) {
            let tablePrefixesByPlate = [
                "cvc_plate_la_barca": "Tavola 1:",
                "cvc_plate_nodi": "Tavola 3:",
                "cvc_plate_manovre_cavi": "Tavola 6:",
                "cvc_plate_direzioni": "Tavola 7:",
                "cvc_plate_rosa_venti": "Tavola 8:",
                "cvc_plate_andature": "Tavola 9:",
                "cvc_plate_scuffia": "Tavola 5:",
                "cvc_plate_panna": "Tavola 21:",
                "cvc_plate_cabinato": "Tavola 33:",
                "cvc_plate_winch_stopper": "Tavola 34:",
            ]
            let item = WordDiagram(
                id: id,
                promptImageName: prompt,
                revealedImageName: revealed,
                title: title,
                plateName: plate,
                plateTitle: plateTitle,
                caption: caption,
                hasMatchingFullPlate: tablePrefixesByPlate[plate].map(plateTitle.hasPrefix) ?? false
            )
            for k in keys {
                dict[normalize(k)] = item
            }
        }

        // --- Tavola 1: La Barca (Deriva) ---
        add(
            keys: ["scafo", "barca", "coperta", "fiancata", "pozzetto", "gavone"],
            id: "scafo",
            prompt: "cvc_crop_scafo_quiz",
            revealed: "cvc_crop_scafo_full",
            title: "Lo Scafo",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Il corpo galleggiante dell'imbarcazione composto da fondo, fiancate, coperta, pozzetto e gavoni."
        )

        add(
            keys: ["chiglia", "carena", "opera viva"],
            id: "chiglia",
            prompt: "cvc_crop_chiglia_quiz",
            revealed: "cvc_crop_chiglia_full",
            title: "La Chiglia",
            plate: "cvc_plate_cabinato",
            plateTitle: "Tavola 33: Il Cabinato",
            caption: "La trave longitudinale inferiore dello scafo; nei cabinati include la pinna fissa zavorrata con bulbo."
        )

        add(
            keys: ["boma", "tesabase"],
            id: "boma",
            prompt: "cvc_crop_boma_quiz",
            revealed: "cvc_crop_boma_full",
            title: "Il Boma",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Asta orizzontale incernierata all'albero su cui è inferita la base della randa e scorre il tesabase."
        )

        add(
            keys: ["albero"],
            id: "albero",
            prompt: "cvc_crop_albero_quiz",
            revealed: "cvc_crop_albero_full",
            title: "L'Albero",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Profilo verticale d'alluminio o legno che sostiene le vele e le manovre."
        )

        add(
            keys: ["timone", "timonare", "timoniere"],
            id: "timone",
            prompt: "cvc_crop_timone_quiz",
            revealed: "cvc_crop_timone_full",
            title: "Il Timone",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Organo di governo poppiero composto da pala, testa, agugliotti e barra."
        )

        add(
            keys: ["barra"],
            id: "barra",
            prompt: "cvc_crop_barra_quiz",
            revealed: "cvc_crop_barra_full",
            title: "La Barra del Timone",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Leva rigida orizzontale montata sulla testa del timone usata per orientare la pala."
        )

        add(
            keys: ["prolunga", "stick"],
            id: "prolunga",
            prompt: "cvc_crop_prolunga_quiz",
            revealed: "cvc_crop_prolunga_full",
            title: "La Prolunga (Stick)",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Asta snodata collegata alla barra che consente al timoniere di timonare sporgendosi alle cinghie."
        )

        add(
            keys: ["deriva"],
            id: "deriva",
            prompt: "cvc_crop_deriva_quiz",
            revealed: "cvc_crop_deriva_full",
            title: "La Deriva",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Profilo alare mobile immerso sotto lo scafo che trasforma lo scarroccio laterale in avanzamento."
        )

        add(
            keys: ["cassa di deriva", "scassa"],
            id: "cassa_deriva",
            prompt: "cvc_crop_cassa_deriva_quiz",
            revealed: "cvc_crop_cassa_deriva_full",
            title: "La Cassa di Deriva",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Involucro stagno centrale nello scafo entro cui scorre o bascula la deriva."
        )

        add(
            keys: ["vang"],
            id: "vang",
            prompt: "cvc_crop_vang_quiz",
            revealed: "cvc_crop_vang_full",
            title: "Il Vang",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Paranco diagonale teso tra piede dell'albero e boma per controllarne l'inclinazione e la svergolatura."
        )

        add(
            keys: ["trozza"],
            id: "trozza",
            prompt: "cvc_crop_trozza_quiz",
            revealed: "cvc_crop_trozza_full",
            title: "La Trozza",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Snodo cardanico che collega il boma all'albero, consentendo rotazione e oscillazione."
        )

        add(
            keys: ["randa"],
            id: "randa",
            prompt: "cvc_crop_randa_quiz",
            revealed: "cvc_crop_randa_full",
            title: "La Randa",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Vela principale a forma triangolare issata lungo l'albero e stesa sopra il boma."
        )

        add(
            keys: ["fiocco", "genoa", "tormentina", "avvolgifiocco"],
            id: "fiocco",
            prompt: "cvc_crop_fiocco_quiz",
            revealed: "cvc_crop_fiocco_full",
            title: "Il Fiocco (Vele di Prua)",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Vela triangolare anteriore (fiocco, genoa o tormentina) inferita sullo strallo o su avvolgifiocco."
        )

        add(
            keys: ["strallo"],
            id: "strallo",
            prompt: "cvc_crop_strallo_quiz",
            revealed: "cvc_crop_strallo_full",
            title: "Lo Strallo",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Cavo fisso d'acciaio che collega la testa o il 3/4 dell'albero alla prua dello scafo."
        )

        add(
            keys: ["sartia", "sartie"],
            id: "sartia",
            prompt: "cvc_crop_sartia_quiz",
            revealed: "cvc_crop_sartia_full",
            title: "La Sartia",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Cavi laterali d'acciaio che sostengono l'albero su ciascun fianco (dritta e sinistra)."
        )

        add(
            keys: ["crocette", "crocetta"],
            id: "crocette",
            prompt: "cvc_crop_crocette_quiz",
            revealed: "cvc_crop_crocette_full",
            title: "Le Crocette",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Distanziali montati sull'albero per allargare l'angolo delle sartie e irrigidire l'albero."
        )

        add(
            keys: ["scotta"],
            id: "scotta",
            prompt: "cvc_crop_scotta_quiz",
            revealed: "cvc_crop_scotta_full",
            title: "La Scotta",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Cavo di manovra corrente usato per regolare l'orientamento delle vele rispetto al vento."
        )

        add(
            keys: ["paranco"],
            id: "paranco",
            prompt: "cvc_crop_paranco_quiz",
            revealed: "cvc_crop_paranco_full",
            title: "Il Paranco",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Combinazione di bozzelli e cime per moltiplicare lo sforzo (es. paranco di scotta randa)."
        )

        add(
            keys: ["drizza", "drizze", "issare", "ammainare"],
            id: "drizza",
            prompt: "cvc_crop_drizza_quiz",
            revealed: "cvc_crop_drizza_full",
            title: "La Drizza",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Cavo corrente che passa sulla puleggia in testa d'albero per issare o ammainare le vele."
        )

        add(
            keys: ["strozzascotte"],
            id: "strozzascotte",
            prompt: "cvc_crop_strozzascotte_quiz",
            revealed: "cvc_crop_strozzascotte_full",
            title: "Lo Strozzascotte",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Dispositivo a camme dentate con molla per bloccare istantaneamente una scotta sotto carico."
        )

        add(
            keys: ["svuotatoio", "sassola", "bugliolo"],
            id: "svuotatoio",
            prompt: "cvc_crop_svuotatoio_quiz",
            revealed: "cvc_crop_svuotatoio_full",
            title: "Lo Svuotatoio (Sassola)",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Valvola sul fondo dello scafo o sassola/bugliolo per espellere o sgottare l'acqua imbarcata."
        )

        add(
            keys: ["falchetta"],
            id: "falchetta",
            prompt: "cvc_crop_falchetta_quiz",
            revealed: "cvc_crop_falchetta_full",
            title: "La Falchetta",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Bordo rialzato longitudinale lungo il perimetro superiore della coperta."
        )

        add(
            keys: ["cinghie puntapiedi", "cinghia puntapiedi", "sbandamento", "sbandare"],
            id: "cinghie_puntapiedi",
            prompt: "cvc_crop_cinghie_puntapiedi_quiz",
            revealed: "cvc_crop_cinghie_puntapiedi_full",
            title: "Le Cinghie Puntapiedi",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Cinghie sul fondo del pozzetto usate per sporgersi all'infuori e contrastare lo sbandamento dello scafo."
        )

        add(
            keys: ["specchio di poppa"],
            id: "specchio_poppa",
            prompt: "cvc_crop_specchio_poppa_quiz",
            revealed: "cvc_crop_specchio_poppa_full",
            title: "Lo Specchio di Poppa",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Superficie piatta o convessa che chiude posteriormente lo scafo e sostiene il timone."
        )

        add(
            keys: ["prua", "prora"],
            id: "prua",
            prompt: "cvc_crop_prua_quiz",
            revealed: "cvc_crop_prua_full",
            title: "La Prua (Prora)",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "La parte anteriore sagomata dello scafo orientata verso la direzione di marcia."
        )

        add(
            keys: ["poppa"],
            id: "poppa",
            prompt: "cvc_crop_poppa_quiz",
            revealed: "cvc_crop_poppa_full",
            title: "La Poppa",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "La parte posteriore dello scafo dove alloggia il timone."
        )

        add(
            keys: ["grillo", "smanigliatore", "moschettone"],
            id: "grillo",
            prompt: "cvc_crop_grillo_quiz",
            revealed: "cvc_crop_grillo_full",
            title: "Il Grillo e Moschettone",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Maniglia metallica a ferro di cavallo chiusa da perno (apribile con smanigliatore) o moschettone rapido."
        )

        add(
            keys: ["galloccia"],
            id: "galloccia",
            prompt: "cvc_crop_galloccia_quiz",
            revealed: "cvc_crop_galloccia_full",
            title: "La Galloccia",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Attacco fisso sagomato a due corni su cui si dà volta a un cavo d'ormeggio o drizza."
        )

        add(
            keys: ["bugna"],
            id: "bugna",
            prompt: "cvc_crop_bugna_quiz",
            revealed: "cvc_crop_bugna_full",
            title: "La Bugna (Punto di Scotta)",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Angolo posteriore basso della vela in cui si applica la trazione della scotta o tesabase."
        )

        add(
            keys: ["punto di mura", "mura"],
            id: "mura",
            prompt: "cvc_crop_mura_quiz",
            revealed: "cvc_crop_mura_full",
            title: "Il Punto di Mura",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Angolo inferiore prodiero della vela, vincolato alla coperta (fiocco) o alla trozza (randa)."
        )

        add(
            keys: ["penna"],
            id: "penna",
            prompt: "cvc_crop_penna_quiz",
            revealed: "cvc_crop_penna_full",
            title: "La Penna (Punto di Drizza)",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Vertice superiore della vela triangolare a cui si aggancia la drizza per issarla."
        )

        add(
            keys: ["balumina"],
            id: "balumina",
            prompt: "cvc_crop_balumina_quiz",
            revealed: "cvc_crop_balumina_full",
            title: "La Balumina",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Bordo libero di uscita posteriore della vela compreso tra la penna e la bugna."
        )

        add(
            keys: ["inferitura"],
            id: "inferitura",
            prompt: "cvc_crop_inferitura_quiz",
            revealed: "cvc_crop_inferitura_full",
            title: "L'Inferitura",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Bordo anteriore d'entrata della vela inferito nella canaletta dell'albero o sullo strallo."
        )

        add(
            keys: ["stecca"],
            id: "stecca",
            prompt: "cvc_crop_stecca_quiz",
            revealed: "cvc_crop_stecca_full",
            title: "La Stecca",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Listello rigido in vetroresina inserito nelle apposite tasche per sostenere l'allunaggio della balumina."
        )

        add(
            keys: ["cunningham"],
            id: "cunningham",
            prompt: "cvc_crop_cunningham_quiz",
            revealed: "cvc_crop_cunningham_full",
            title: "Il Cunningham",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Occhiello sopra la mura e relativo paranco per regolare la tensione dell'inferitura della randa."
        )

        add(
            keys: ["terzarolo", "terzaroli", "mano di terzaroli", "matafioni", "borosa"],
            id: "terzaroli",
            prompt: "cvc_crop_terzaroli_quiz",
            revealed: "cvc_crop_terzaroli_full",
            title: "I Terzaroli",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Sistema di riduzione della superficie velica della randa con vento forte."
        )

        // --- Tavola 3: I Nodi ---
        add(
            keys: ["gassa d'amante"],
            id: "gassa_damante",
            prompt: "cvc_crop_gassa_damante_quiz",
            revealed: "cvc_crop_gassa_damante_full",
            title: "La Gassa d'Amante",
            plate: "cvc_plate_nodi",
            plateTitle: "Tavola 3: I Nodi (CVC)",
            caption: "Il nodo per eccellenza: crea un occhio fisso che non stringe e non scorre mai su se stesso."
        )

        add(
            keys: ["nodo a otto", "nodo savoia", "nodo", "nodi", "fune", "sfilarsi"],
            id: "nodo_otto",
            prompt: "cvc_crop_nodo_otto_quiz",
            revealed: "cvc_crop_nodo_otto_full",
            title: "Il Nodo a Otto (Savoia)",
            plate: "cvc_plate_nodi",
            plateTitle: "Tavola 3: I Nodi (CVC)",
            caption: "Nodo d'arresto eseguito all'estremità di una fune o scotta per impedirne lo sfilamento dal passascotte."
        )

        add(
            keys: ["nodo parlato"],
            id: "nodo_parlato",
            prompt: "cvc_crop_nodo_parlato_quiz",
            revealed: "cvc_crop_nodo_parlato_full",
            title: "Il Nodo Parlato",
            plate: "cvc_plate_nodi",
            plateTitle: "Tavola 3: I Nodi (CVC)",
            caption: "Nodo d'avvolgimento per legare rapidamente un cavo a un'asta, tubo o bitta (usato per i parabordi)."
        )

        add(
            keys: ["nodo piano"],
            id: "nodo_piano",
            prompt: "cvc_crop_nodo_piano_quiz",
            revealed: "cvc_crop_nodo_piano_full",
            title: "Il Nodo Piano",
            plate: "cvc_plate_nodi",
            plateTitle: "Tavola 3: I Nodi (CVC)",
            caption: "Nodo di giunzione simmetrico per unire due cavi di uguale diametro (es. matafioni di terzarolo)."
        )

        add(
            keys: ["nodo di scotta", "nodo a bandiera"],
            id: "nodo_scotta",
            prompt: "cvc_crop_nodo_scotta_quiz",
            revealed: "cvc_crop_nodo_scotta_full",
            title: "Il Nodo di Scotta (Bandiera)",
            plate: "cvc_plate_nodi",
            plateTitle: "Tavola 3: I Nodi (CVC)",
            caption: "Nodo per collegare due cime di diametro differente; molto affidabile anche sotto forte carico."
        )

        add(
            keys: ["due mezzi colli"],
            id: "due_mezzi_colli",
            prompt: "cvc_crop_due_mezzi_colli_quiz",
            revealed: "cvc_crop_due_mezzi_colli_full",
            title: "I Due Mezzi Colli",
            plate: "cvc_plate_nodi",
            plateTitle: "Tavola 3: I Nodi (CVC)",
            caption: "Nodo d'avvolgimento sicuro per dare volta su anelli o cime in tensione."
        )

        // --- Manovre Cavi ---
        add(
            keys: ["dare volta", "mollare", "filare", "alare", "agguantare"],
            id: "dare_volta",
            prompt: "cvc_crop_dare_volta_quiz",
            revealed: "cvc_crop_dare_volta_full",
            title: "Dare Volta su Galloccia",
            plate: "cvc_plate_manovre_cavi",
            plateTitle: "Manovre con i cavi",
            caption: "Fissare o manovrare un cavo su galloccia (alare, filare, mollare o dare volta)."
        )

        add(
            keys: ["addugliare", "mettere in chiaro"],
            id: "addugliare",
            prompt: "cvc_crop_addugliare_quiz",
            revealed: "cvc_crop_addugliare_full",
            title: "Addugliare una Cima (Mettere in Chiaro)",
            plate: "cvc_plate_manovre_cavi",
            plateTitle: "Manovre con i cavi",
            caption: "Raccogliere o stendere in chiaro un cavo formando spire ordinate (duglie) pronte a scorrere."
        )

        // --- Tavola 7: Direzioni & Vento ---
        add(
            keys: ["a dritta"],
            id: "a_dritta",
            prompt: "cvc_crop_a_dritta_quiz",
            revealed: "cvc_crop_a_dritta_full",
            title: "A Dritta",
            plate: "cvc_plate_direzioni",
            plateTitle: "Tavola 7: Le Direzioni",
            caption: "Il lato destro dell'imbarcazione rivolto verso prora (contrassegnato dal fanale verde)."
        )

        add(
            keys: ["a sinistra"],
            id: "a_sinistra",
            prompt: "cvc_crop_a_sinistra_quiz",
            revealed: "cvc_crop_a_sinistra_full",
            title: "A Sinistra",
            plate: "cvc_plate_direzioni",
            plateTitle: "Tavola 7: Le Direzioni",
            caption: "Il lato sinistro dell'imbarcazione rivolto verso prora (contrassegnato dal fanale rosso)."
        )

        add(
            keys: ["mascone"],
            id: "mascone",
            prompt: "cvc_crop_mascone_quiz",
            revealed: "cvc_crop_mascone_full",
            title: "Il Mascone",
            plate: "cvc_plate_direzioni",
            plateTitle: "Tavola 7: Le Direzioni",
            caption: "Settore della fiancata compreso tra la prora e il traverso (a circa 45° dalla prora)."
        )

        add(
            keys: ["giardinetto"],
            id: "giardinetto",
            prompt: "cvc_crop_giardinetto_quiz",
            revealed: "cvc_crop_giardinetto_full",
            title: "Il Giardinetto",
            plate: "cvc_plate_direzioni",
            plateTitle: "Tavola 7: Le Direzioni",
            caption: "Settore della fiancata compreso tra il traverso e la poppa (a circa 45° dalla poppa)."
        )

        add(
            keys: ["traverso"],
            id: "traverso",
            prompt: "cvc_crop_traverso_quiz",
            revealed: "cvc_crop_traverso_full",
            title: "Il Traverso",
            plate: "cvc_plate_direzioni",
            plateTitle: "Tavola 7: Le Direzioni",
            caption: "Direzione a 90° rispetto all'asse longitudinale della barca (ore 3 o ore 9)."
        )

        add(
            keys: ["sopravvento"],
            id: "sopravvento",
            prompt: "cvc_crop_sopravvento_quiz",
            revealed: "cvc_crop_sopravvento_full",
            title: "Sopravvento",
            plate: "cvc_plate_direzioni",
            plateTitle: "Tavola 7: Il Vento",
            caption: "Il lato o settore dal quale spira e giunge il vento rispetto all'imbarcazione."
        )

        add(
            keys: ["sottovento"],
            id: "sottovento",
            prompt: "cvc_crop_sottovento_quiz",
            revealed: "cvc_crop_sottovento_full",
            title: "Sottovento",
            plate: "cvc_plate_direzioni",
            plateTitle: "Tavola 7: Il Vento",
            caption: "Il lato o settore verso cui fugge e spira il vento rispetto all'imbarcazione."
        )

        add(
            keys: ["orzare", "straorzata"],
            id: "orzare",
            prompt: "cvc_crop_orzare_quiz",
            revealed: "cvc_crop_orzare_full",
            title: "Orzare e Straorzata",
            plate: "cvc_plate_direzioni",
            plateTitle: "Tavola 7: Il Vento",
            caption: "Avvicinare la prora al vento; la straorzata è l'orzata violenta e incontrollata causata da raffica."
        )

        add(
            keys: ["poggiare"],
            id: "poggiare",
            prompt: "cvc_crop_poggiare_quiz",
            revealed: "cvc_crop_poggiare_full",
            title: "Poggiare",
            plate: "cvc_plate_direzioni",
            plateTitle: "Tavola 7: Il Vento",
            caption: "Allontanare la prora dalla provenienza del vento spingendo la barra all'infuori."
        )

        add(
            keys: ["mure a dritta", "mure a sinistra"],
            id: "mure_dritta",
            prompt: "cvc_crop_mure_dritta_quiz",
            revealed: "cvc_crop_mure_dritta_full",
            title: "Le Mure (Dritta / Sinistra)",
            plate: "cvc_plate_direzioni",
            plateTitle: "Tavola 7: Il Vento",
            caption: "Mure a dritta: la barca riceve il vento dal lato destro (ha diritto di precedenza)."
        )

        // --- Tavola 8: La Rosa dei Venti ---
        add(
            keys: ["rosa dei venti", "bussola"],
            id: "rosa_dei_venti",
            prompt: "cvc_crop_rosa_dei_venti_quiz",
            revealed: "cvc_crop_rosa_dei_venti_full",
            title: "La Rosa dei Venti (Bussola)",
            plate: "cvc_plate_rosa_venti",
            plateTitle: "Tavola 8: Rosa dei Venti",
            caption: "La mappa tradizionale dei venti del Mediterraneo e orientamento dei 360° della bussola."
        )

        add(
            keys: ["maestrale"],
            id: "maestrale",
            prompt: "cvc_crop_maestrale_quiz",
            revealed: "cvc_crop_maestrale_full",
            title: "Il Maestrale (NW - 315°)",
            plate: "cvc_plate_rosa_venti",
            plateTitle: "Tavola 8: Rosa dei Venti",
            caption: "Vento dominante da Nord-Ovest, fresco e secco, celebre nelle acque di Caprera."
        )

        add(
            keys: ["scirocco"],
            id: "scirocco",
            prompt: "cvc_crop_scirocco_quiz",
            revealed: "cvc_crop_scirocco_full",
            title: "Lo Scirocco (SE - 135°)",
            plate: "cvc_plate_rosa_venti",
            plateTitle: "Tavola 8: Rosa dei Venti",
            caption: "Vento caldo e umido proveniente dal deserto a Sud-Est."
        )

        add(
            keys: ["tramontana"],
            id: "tramontana",
            prompt: "cvc_crop_tramontana_quiz",
            revealed: "cvc_crop_tramontana_full",
            title: "La Tramontana (N - 0°)",
            plate: "cvc_plate_rosa_venti",
            plateTitle: "Tavola 8: Rosa dei Venti",
            caption: "Vento freddo e pungente proveniente direttamente da Nord."
        )

        add(
            keys: ["libeccio"],
            id: "libeccio",
            prompt: "cvc_crop_libeccio_quiz",
            revealed: "cvc_crop_libeccio_full",
            title: "Il Libeccio (SW - 225°)",
            plate: "cvc_plate_rosa_venti",
            plateTitle: "Tavola 8: Rosa dei Venti",
            caption: "Vento rafficato e mareggiato da Sud-Ovest, tipico delle coste occidentali italiane."
        )

        add(
            keys: ["ponente"],
            id: "ponente",
            prompt: "cvc_crop_ponente_quiz",
            revealed: "cvc_crop_ponente_full",
            title: "Il Ponente (W - 270°)",
            plate: "cvc_plate_rosa_venti",
            plateTitle: "Tavola 8: Rosa dei Venti",
            caption: "Vento spirante dal settore occidentale (tramonto)."
        )

        add(
            keys: ["levante"],
            id: "levante",
            prompt: "cvc_crop_levante_quiz",
            revealed: "cvc_crop_levante_full",
            title: "Il Levante (E - 90°)",
            plate: "cvc_plate_rosa_venti",
            plateTitle: "Tavola 8: Rosa dei Venti",
            caption: "Vento proveniente dall'oriente (alba)."
        )

        add(
            keys: ["grecale", "bora"],
            id: "grecale",
            prompt: "cvc_crop_grecale_quiz",
            revealed: "cvc_crop_grecale_full",
            title: "Il Grecale e la Bora (NE - 45°)",
            plate: "cvc_plate_rosa_venti",
            plateTitle: "Tavola 8: Rosa dei Venti",
            caption: "Vento freddo e impetuoso da Nord-Est (direzione della Grecia e dell'alto Adriatico)."
        )

        add(
            keys: ["ostro"],
            id: "ostro",
            prompt: "cvc_crop_ostro_quiz",
            revealed: "cvc_crop_ostro_full",
            title: "L'Ostro (S - 180°)",
            plate: "cvc_plate_rosa_venti",
            plateTitle: "Tavola 8: Rosa dei Venti",
            caption: "Vento mite da Sud (Mezzogiorno)."
        )

        add(
            keys: ["brezza di mare"],
            id: "brezza_mare",
            prompt: "cvc_crop_brezza_mare_quiz",
            revealed: "cvc_crop_brezza_mare_full",
            title: "La Brezza di Mare",
            plate: "cvc_plate_rosa_venti",
            plateTitle: "Tavola 8: Le Brezze",
            caption: "Vento termico che si alza a metà giornata dal mare verso terra per convezione solare."
        )

        add(
            keys: ["brezza di terra"],
            id: "brezza_terra",
            prompt: "cvc_crop_brezza_terra_quiz",
            revealed: "cvc_crop_brezza_terra_full",
            title: "La Brezza di Terra",
            plate: "cvc_plate_rosa_venti",
            plateTitle: "Tavola 8: Le Brezze",
            caption: "Vento termico notturno che spira dalla terra raffreddata verso il mare più caldo."
        )

        // --- Tavola 9: Andature e Regolazione ---
        add(
            keys: ["andatura", "andature", "spinnaker"],
            id: "andatura",
            prompt: "cvc_crop_andatura_quiz",
            revealed: "cvc_crop_andatura_full",
            title: "Le Andature",
            plate: "cvc_plate_andature",
            plateTitle: "Tavola 9: Andature e Vele",
            caption: "Rapporto angolare tra rotta della barca e direzione del vento (bolina, traverso, lasco, poppa con spinnaker)."
        )

        add(
            keys: ["angolo morto", "letto del vento", "pungere"],
            id: "angolo_morto",
            prompt: "cvc_crop_angolo_morto_quiz",
            revealed: "cvc_crop_angolo_morto_full",
            title: "L'Angolo Morto (Letto del Vento)",
            plate: "cvc_plate_andature",
            plateTitle: "Tavola 9: Andature e Vele",
            caption: "Settore di circa 90° rivolto al letto del vento dove la barca non può avanzare; 'pungere' significa avvicinarsi troppo a questo limite."
        )

        add(
            keys: ["bolina", "bolina stretta", "bolina larga"],
            id: "bolina",
            prompt: "cvc_crop_bolina_quiz",
            revealed: "cvc_crop_bolina_full",
            title: "La Bolina",
            plate: "cvc_plate_andature",
            plateTitle: "Tavola 9: Andature e Vele",
            caption: "L'andatura che risale il vento al massimo angolo possibile (~45°) con le vele cazzate strette."
        )

        add(
            keys: ["lasco", "gran lasco", "fil di ruota", "a farfalla", "vento a favore"],
            id: "lasco",
            prompt: "cvc_crop_lasco_quiz",
            revealed: "cvc_crop_lasco_full",
            title: "Il Lasco e Fil di Ruota (A Farfalla)",
            plate: "cvc_plate_andature",
            plateTitle: "Tavola 9: Andature e Vele",
            caption: "Andature portanti con vento a favore; in fil di ruota (poppa piena) le vele possono essere esposte a farfalla."
        )

        add(
            keys: ["mettere a segno", "bordare", "fileggiare", "sventare", "cazzare", "lascare"],
            id: "mettere_a_segno",
            prompt: "cvc_crop_mettere_a_segno_quiz",
            revealed: "cvc_crop_mettere_a_segno_full",
            title: "Mettere a Segno le Vele",
            plate: "cvc_plate_andature",
            plateTitle: "Tavola 9: Regolazione",
            caption: "Lascare fino a far fileggiare l'inferitura, poi cazzare appena per ottenere il flusso laminare massimo."
        )

        // --- Tavola 5 & 21: Scuffia, Raddrizzare, Panna ---
        add(
            keys: ["scuffia", "scuffiare"],
            id: "scuffia",
            prompt: "cvc_crop_scuffia_quiz",
            revealed: "cvc_crop_scuffia_full",
            title: "La Scuffia (Capsize)",
            plate: "cvc_plate_scuffia",
            plateTitle: "Tavola 5: Scuffia e Sicurezza",
            caption: "Rovesciamento della deriva su un fianco: mantenere il contatto e non allontanarsi mai dallo scafo."
        )

        add(
            keys: ["raddrizzare", "raddrizzamento"],
            id: "raddrizzare",
            prompt: "cvc_crop_raddrizzare_quiz",
            revealed: "cvc_crop_raddrizzare_full",
            title: "Il Raddrizzamento",
            plate: "cvc_plate_scuffia",
            plateTitle: "Tavola 5: Scuffia e Sicurezza",
            caption: "Manovra per drizzare la barca salendo sulla pala di deriva e facendo leva con il proprio peso."
        )

        add(
            keys: ["in panna", "alla cappa"],
            id: "in_panna",
            prompt: "cvc_crop_in_panna_quiz",
            revealed: "cvc_crop_in_panna_full",
            title: "La Panna (Alla Cappa)",
            plate: "cvc_plate_panna",
            plateTitle: "Tavola 21: La Panna",
            caption: "Assetto di stazionamento stabile (mettersi alla cappa) con fiocco a collo, randa libera e barra all'orza."
        )

        // --- Tavola 33 & 34: Cabinato, Winch e Stopper ---
        add(
            keys: ["tuga"],
            id: "tuga",
            prompt: "cvc_crop_tuga_quiz",
            revealed: "cvc_crop_tuga_full",
            title: "La Tuga",
            plate: "cvc_plate_cabinato",
            plateTitle: "Tavola 33: Il Cabinato",
            caption: "La sovrastruttura sagomata sopra la coperta che garantisce altezza e luminosità all'interno."
        )

        add(
            keys: ["tambuccio"],
            id: "tambuccio",
            prompt: "cvc_crop_tambuccio_quiz",
            revealed: "cvc_crop_tambuccio_full",
            title: "Il Tambuccio",
            plate: "cvc_plate_cabinato",
            plateTitle: "Tavola 33: Il Cabinato",
            caption: "Chiusura scorrevole orizzontale della discesa dal pozzetto nella cabina."
        )

        add(
            keys: ["bulbo"],
            id: "bulbo",
            prompt: "cvc_crop_bulbo_quiz",
            revealed: "cvc_crop_bulbo_full",
            title: "Il Bulbo di Zavorra",
            plate: "cvc_plate_cabinato",
            plateTitle: "Tavola 33: Il Cabinato",
            caption: "Zavorra pesante in piombo o ghisa sul fondo della chiglia che conferisce raddrizzamento al cabinato."
        )

        add(
            keys: ["pulpito"],
            id: "pulpito",
            prompt: "cvc_crop_pulpito_quiz",
            revealed: "cvc_crop_pulpito_full",
            title: "Il Pulpito di Prua",
            plate: "cvc_plate_cabinato",
            plateTitle: "Tavola 33: Il Cabinato",
            caption: "Ringhiera d'acciaio tubolare fissata sulla prora a protezione dell'equipaggio."
        )

        add(
            keys: ["balcone"],
            id: "balcone",
            prompt: "cvc_crop_balcone_quiz",
            revealed: "cvc_crop_balcone_full",
            title: "Il Balcone di Poppa",
            plate: "cvc_plate_cabinato",
            plateTitle: "Tavola 33: Il Cabinato",
            caption: "Pulpito poppiero d'acciaio inox situato a poppa sopra lo specchio."
        )

        add(
            keys: ["candeliere", "candelieri"],
            id: "candeliere",
            prompt: "cvc_crop_candeliere_quiz",
            revealed: "cvc_crop_candeliere_full",
            title: "Il Candeliere",
            plate: "cvc_plate_cabinato",
            plateTitle: "Tavola 33: Il Cabinato",
            caption: "Asta d'acciaio verticale inserita sul bordo della coperta che guida le draglie di sicurezza."
        )

        add(
            keys: ["draglia", "draglie", "battagliola", "life line", "cintura di sicurezza"],
            id: "draglia",
            prompt: "cvc_crop_draglia_quiz",
            revealed: "cvc_crop_draglia_full",
            title: "Le Draglie e Battagliola",
            plate: "cvc_plate_cabinato",
            plateTitle: "Tavola 33: Il Cabinato",
            caption: "Cavi d'acciaio rivestiti tesi tra i candelieri per formare la battagliola e agganciare la life line."
        )

        add(
            keys: ["parabordo", "parabordi"],
            id: "parabordo",
            prompt: "cvc_crop_parabordo_quiz",
            revealed: "cvc_crop_parabordo_full",
            title: "Il Parabordo",
            plate: "cvc_plate_cabinato",
            plateTitle: "Tavola 33: Il Cabinato",
            caption: "Cilindro gonfiabile sospeso lungo la fiancata con un nodo parlato per riparare lo scafo."
        )

        add(
            keys: ["paterazzo"],
            id: "paterazzo",
            prompt: "cvc_crop_paterazzo_quiz",
            revealed: "cvc_crop_paterazzo_full",
            title: "Il Paterazzo",
            plate: "cvc_plate_cabinato",
            plateTitle: "Tavola 33: Il Cabinato",
            caption: "Cavo d'acciaio fisso che scende dalla testa d'albero allo specchio di poppa per contrastare lo strallo."
        )

        add(
            keys: ["winch"],
            id: "winch",
            prompt: "cvc_crop_winch_quiz",
            revealed: "cvc_crop_winch_full",
            title: "Il Winch",
            plate: "cvc_plate_winch_stopper",
            plateTitle: "Tavola 34: Winch e Stopper",
            caption: "Argano a tamburo demoliplicatore: avvolgere la cima sempre in senso orario (almeno 3 giri)."
        )

        add(
            keys: ["stopper"],
            id: "stopper",
            prompt: "cvc_crop_stopper_quiz",
            revealed: "cvc_crop_stopper_full",
            title: "Lo Stopper",
            plate: "cvc_plate_winch_stopper",
            plateTitle: "Tavola 34: Winch e Stopper",
            caption: "Bloccacavo a leva per serrare cime sotto carico (drizze, borose) lasciando libero il winch."
        )

        // --- Tavola 16: Virata in Prua ---
        add(
            keys: ["virata", "virare"],
            id: "virata",
            prompt: "cvc_crop_virata_quiz",
            revealed: "cvc_crop_virata_full",
            title: "La Virata in Prua",
            plate: "cvc_plate_direzioni",
            plateTitle: "Tavola 16: La Virata",
            caption: "Manovra che consiste nel far passare la prua attraverso il letto del vento per cambiare mure."
        )

        // --- Tavola 18: La Strambata ---
        add(
            keys: ["strambata", "strambare", "abbattuta"],
            id: "strambata",
            prompt: "cvc_crop_strambata_quiz",
            revealed: "cvc_crop_strambata_full",
            title: "La Strambata (Abbattuta)",
            plate: "cvc_plate_direzioni",
            plateTitle: "Tavola 18: La Strambata",
            caption: "Manovra in andatura portante che consiste nel far passare la poppa attraverso il vento per cambiare mure."
        )

        // --- Tavola 21: Vento Reale e Apparente ---
        add(
            keys: ["vento reale", "vento apparente", "vento di velocità"],
            id: "vento_reale_apparente",
            prompt: "cvc_crop_vento_reale_apparente_quiz",
            revealed: "cvc_crop_vento_reale_apparente_full",
            title: "Vento Reale e Apparente",
            plate: "cvc_plate_direzioni",
            plateTitle: "Tavola 21: Vento Reale e Vento Apparente",
            caption: "Il vento apparente percepito a bordo è la somma vettoriale del vento reale e del vento di avanzamento."
        )

        // --- Tavola 13: Risalire il Vento e Scarroccio ---
        add(
            keys: ["scarroccio", "scarrocciare", "bordeggiare", "bordeggio", "bordo"],
            id: "scarroccio_bordeggio",
            prompt: "cvc_crop_scarroccio_bordeggio_quiz",
            revealed: "cvc_crop_scarroccio_bordeggio_full",
            title: "Bordeggio e Scarroccio",
            plate: "cvc_plate_andature",
            plateTitle: "Tavola 13: Risalire il Vento",
            caption: "Bordeggiare a zig-zag controvento; lo scarroccio è lo scivolamento laterale sottovento compensato dalla deriva."
        )

        // --- Tavola 24: Manovra Uomo in Mare ---
        add(
            keys: ["uomo in mare", "salvagente", "giubbotto salvagente"],
            id: "uomo_in_mare",
            prompt: "cvc_crop_uomo_in_mare_quiz",
            revealed: "cvc_crop_uomo_in_mare_full",
            title: "Uomo in Mare",
            plate: "cvc_plate_scuffia",
            plateTitle: "Tavola 24: Recupero Uomo in Mare",
            caption: "Manovra di sicurezza (virata o percorso a otto) per invertire la rotta e fermarsi sottovento al naufrago."
        )

        // --- Tavola 41: L'Ancoraggio ---
        add(
            keys: ["ancora", "ancorotto", "ancorare", "ancoraggio", "dare fondo", "cablotto", "a picco", "spedare"],
            id: "ancora",
            prompt: "cvc_crop_ancora_quiz",
            revealed: "cvc_crop_ancora_full",
            title: "L'Ancora e Ancoraggio",
            plate: "cvc_plate_cabinato",
            plateTitle: "Tavola 41: L'Ormeggio all'Ancora",
            caption: "Attrezzo da fondo con calumo (catena e cablotto) pari ad almeno 3-5 volte la profondità."
        )

        // --- Tavola 27: Presa di Gavitello ---
        add(
            keys: ["gavitello", "corpo morto", "barbetta", "abbrivo", "abbrivare"],
            id: "gavitello",
            prompt: "cvc_crop_gavitello_quiz",
            revealed: "cvc_crop_gavitello_full",
            title: "Il Gavitello e l'Abbrivo",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 27: Presa di Gavitello",
            caption: "Galleggiante ormeggiato al corpo morto; ci si avvicina prua al vento sfruttando l'abbrivo (inerzia di moto) per fermarsi al gavitello."
        )

        // --- Tavola 33: Amantiglio, Mostravento, Oblò ---
        add(
            keys: ["amantiglio"],
            id: "amantiglio",
            prompt: "cvc_crop_amantiglio_quiz",
            revealed: "cvc_crop_amantiglio_full",
            title: "L'Amantiglio",
            plate: "cvc_plate_cabinato",
            plateTitle: "Tavola 33: Il Cabinato",
            caption: "Cavo dalla testa d'albero al terminale del boma per sostenerlo a riposo con randa ammainata."
        )

        add(
            keys: ["mostravento", "tell-tales", "segnavento"],
            id: "mostravento",
            prompt: "cvc_crop_mostravento_quiz",
            revealed: "cvc_crop_mostravento_full",
            title: "Mostravento e Tell-tales",
            plate: "cvc_plate_cabinato",
            plateTitle: "Tavola 33: Il Cabinato",
            caption: "Filetti in lana o nastro su vele o stralli che indicano l'andamento laminare del flusso del vento."
        )

        add(
            keys: ["oblò", "osteriggio"],
            id: "oblo",
            prompt: "cvc_crop_oblo_quiz",
            revealed: "cvc_crop_oblo_full",
            title: "L'Oblò e l'Osteriggio",
            plate: "cvc_plate_cabinato",
            plateTitle: "Tavola 33: Il Cabinato",
            caption: "Portelli e aperture stagne trasparenti per illuminazione e ricambio d'aria degli interni."
        )

        // --- Tavola 6: Bitta e Bitte ---
        add(
            keys: ["bitta", "bitte"],
            id: "bitta",
            prompt: "cvc_crop_bitta_quiz",
            revealed: "cvc_crop_bitta_full",
            title: "La Bitta",
            plate: "cvc_plate_manovre_cavi",
            plateTitle: "Tavola 6: Manovre dei Cavi",
            caption: "Colonnina di coperta o banchina per dare volta e serrare le cime d'ormeggio con un mezzo collo."
        )

        // --- Tavola 1 & 4: Bozzello ---
        add(
            keys: ["bozzello", "bozzelli"],
            id: "bozzello",
            prompt: "cvc_crop_bozzello_quiz",
            revealed: "cvc_crop_bozzello_full",
            title: "Il Bozzello",
            plate: "cvc_plate_la_barca",
            plateTitle: "Tavola 1: La Barca (Deriva)",
            caption: "Puleggia marinaresca per rinvio e scorrimento a basso attrito di scotte, drizze e paranchi."
        )

        return dict
    }()

    private static func normalize(_ str: String) -> String {
        var clean = str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Remove common Italian articles
        let articles = ["il ", "lo ", "la ", "l'", "i ", "gli ", "le ", "un ", "uno ", "una "]
        for art in articles {
            if clean.hasPrefix(art) {
                clean = String(clean.dropFirst(art.count))
                break
            }
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func diagram(for italianWord: String) -> WordDiagram? {
        let norm = normalize(italianWord)
        if let direct = diagrams[norm] {
            return direct
        }
        // Substring fallback if word contains key (e.g. "dare volta su una galloccia")
        for (key, diagram) in diagrams {
            if norm == key || norm.hasPrefix(key + " ") || norm.hasSuffix(" " + key) {
                return diagram
            }
        }
        return nil
    }

    public static var allDiagrams: [WordDiagram] {
        var seen = Set<String>()
        var list: [WordDiagram] = []
        for diag in diagrams.values {
            if seen.insert(diag.id).inserted {
                list.append(diag)
            }
        }
        return list
    }

    public static func visualQuizOptions(for italianWord: String, count: Int = 4) -> (target: WordDiagram, options: [WordDiagram])? {
        guard let target = diagram(for: italianWord) else { return nil }

        var selectedDistractors: [WordDiagram] = []
        var usedPromptImages = Set<String>([target.promptImageName])
        var usedIds = Set<String>([target.id])

        // 1. Prioritize distractors from the same diagram plate
        let samePlateCandidates = allDiagrams
            .filter { $0.plateName == target.plateName && !usedIds.contains($0.id) }
            .shuffled()

        for diag in samePlateCandidates {
            guard selectedDistractors.count < count - 1 else { break }
            if !usedPromptImages.contains(diag.promptImageName) {
                selectedDistractors.append(diag)
                usedPromptImages.insert(diag.promptImageName)
                usedIds.insert(diag.id)
            }
        }

        // 2. Fallback to other plates if the same plate has fewer items than needed
        if selectedDistractors.count < count - 1 {
            let otherPlateCandidates = allDiagrams
                .filter { $0.plateName != target.plateName && !usedIds.contains($0.id) }
                .shuffled()

            for diag in otherPlateCandidates {
                guard selectedDistractors.count < count - 1 else { break }
                if !usedPromptImages.contains(diag.promptImageName) {
                    selectedDistractors.append(diag)
                    usedPromptImages.insert(diag.promptImageName)
                    usedIds.insert(diag.id)
                }
            }
        }

        var options = selectedDistractors
        options.append(target)
        options.shuffle()

        return (target, options)
    }
}
