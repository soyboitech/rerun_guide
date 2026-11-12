' Port of web/src/core/DemoServer.ts: the fixed, invented library of the Sample station, so the whole app runs without a
' server. 20 films and 3 shows of 8 episodes, arranged so every automatic channel type shows up.

function DemoServer_libraries() as Object
    return [
        {id: "demo-movies", title: "Movies", kind: "movies", itemCount: 20},
        {id: "demo-tv", title: "TV Shows", kind: "shows", itemCount: 3}
    ]
end function

' A fixed sample stream that starts at its own beginning (startsAtOffset): nobody seeks it to the clock's offset, and
' the player loops it.
function DemoServer_playbackURL() as String
    return "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"
end function

' The library, with `addedAt` counted back from `loaded` (one film every 6 days, so about 10 are Just Added).
function DemoServer_items(loaded = invalid as Dynamic) as Object
    if loaded = invalid then loaded = Time_now()
    vole = "Marguerite Vole"
    calhoun = "Dusty Calhoun"
    okonkwo = "Len Okonkwo"
    marsh = "Priya Marsh"
    rex = "Rex Tallow"
    dolores = "Dolores Finch"
    kip = "Kip Navarro"
    bea = "Bea Saltonstall"
    hal = "Hal Pruett"
    wendell = "Wendell Ash"
    nina = "Nina Castellano"
    ozzie = "Ozzie Blankenship"
    films = [
        [1, "Night of the Rental Returns", 1985, 92, "R", ["Horror", "Comedy"], vole, [rex, dolores], "A video-store night clerk discovers the overdue tapes are coming back on their own, and they are angry about the late fees."],
        [2, "Chrome Horizon", 1984, 118, "PG", ["Sci-Fi"], vole, [kip, bea], "A test pilot flies a prototype past the edge of the atmosphere and finds a second, mirrored Earth waiting there."],
        [3, "The Last Payphone", 1996, 104, "R", ["Drama"], okonkwo, [dolores, hal], "A night-shift dispatcher keeps answering the one payphone in town nobody else will pick up."],
        [4, "Mullet Force", 1985, 97, "PG-13", ["Action", "Comedy"], calhoun, [rex, kip], "Four hairdressers with military pasts are the only ones who can stop a hostile takeover of the state fair."],
        [5, "Suburban Meteor", 1991, 101, "PG", ["Sci-Fi", "Comedy"], vole, [rex, bea], "A meteorite lands in a cul-de-sac and the homeowners' association wants it moved by Friday."],
        [6, "Blood on the Boardwalk", 1982, 88, "R", ["Horror"], vole, [dolores, wendell], "Something under the pier is picking off carnival workers one summer night at a time."],
        [7, "Dial Tone", 1993, 110, "PG-13", ["Drama"], marsh, [dolores, kip], "A phone-company lineman starts hearing a stranger's confessions on a crossed wire and can't stop listening."],
        [8, "Rooftop Reckoning", 1990, 112, "R", ["Action", "Crime"], calhoun, [rex, hal], "A window washer trapped forty stories up becomes the only witness to a heist in progress."],
        [9, "The Beige Conspiracy", 1978, 126, "PG", ["Drama"], okonkwo, [bea, hal], "A junior accountant notices every office in the building is painted the same color, and starts asking why."],
        [10, "Laser Prom", 1985, 95, "PG", ["Sci-Fi", "Comedy"], calhoun, [kip, dolores], "The prom committee's borrowed light show turns out to be alien technology with opinions about the playlist."],
        [11, "Static", 1998, 99, "R", ["Horror"], vole, [wendell, nina], "A late-night radio engineer realizes the dead air between stations has started to talk back."],
        [12, "Two Tickets to Tuesday", 1995, 93, "PG", ["Comedy"], marsh, [dolores, rex], "Two strangers hold the same winning raffle ticket and have one week to decide who gets the cruise."],
        [13, "Iron Cul-de-Sac", 1988, 108, "R", ["Action"], calhoun, [rex, nina], "A retired demolition expert defends his street from developers using everything in his garage."],
        [14, "Orbital Lullaby", 1997, 132, "PG-13", ["Sci-Fi", "Drama"], okonkwo, [kip, wendell], "The last crew member awake on a sleeper ship has to decide whether to wake the others for the view."],
        [15, "The Cassette Killer", 1985, 90, "R", ["Horror"], vole, [dolores, kip], "Every mixtape left on the diner counter plays a song the listener will never finish."],
        [16, "Floodlight", 1979, 140, "PG", ["Drama"], marsh, [nina, ozzie], "A small-town stadium's night-game lights become the center of a fight over who the town belongs to."],
        [17, "Big Hair, Bigger Trouble", 1992, 85, "PG-13", ["Comedy"], calhoun, [rex, dolores], "A salon owner's regional styling title is challenged by her own twin sister."],
        [18, "Harbor Protocol", 1994, 121, "R", ["Action", "Drama", "Crime"], calhoun, [kip, ozzie], "A harbor master with one night left before retirement finds a cargo manifest that doesn't add up."],
        [19, "Moonbase Midnight", 1981, 103, "PG-13", ["Sci-Fi", "Horror"], vole, [ozzie, rex], "The night crew of a lunar mining base discovers their shift has been running for three years."],
        [20, "Reunion Weekend", 1999, 96, "PG", ["Comedy", "Drama"], okonkwo, [dolores, kip], "A class reunion at a motel with one working ice machine forces old friends to settle twenty years of accounts."]
    ]
    items = []
    for each f in films
        items.Push(MediaItem_new({id: "m" + iStr(f[0]), kind: "movie", title: f[1], year: f[2], genres: f[5], runtime: f[3] * 60,
            overview: f[8], contentRating: f[4], directors: [f[6]], actors: f[7], libraryID: "demo-movies",
            addedAt: loaded - f[0] * 6 * 86400#}))
    end for
    DS_series(items, "cds", "Cul-de-Sac Confidential", 1988, 22, ["Comedy"], [
        [1, 1, "The Welcome Casserole", "The new neighbors get a casserole from every house on the street, and every cook wants their dish back first."],
        [1, 2, "Garage Sale Gambit", "A joint garage sale turns competitive when one driveway starts offering free lemonade."],
        [1, 3, "Sprinkler Wars", "Two lawns, one shared water line, and a watering schedule nobody agreed to."],
        [1, 4, "The Mailbox Incident", "A misdelivered package reveals which neighbor has been ordering the same novelty item for years."],
        [1, 5, "Block Party Blues", "The block party band breaks up during sound check."],
        [1, 6, "Hedge Fund", "The street pools money for a hedge trimmer and immediately argues about custody."],
        [1, 7, "Carpool Confessions", "A stalled carpool van becomes a confessional on the longest morning commute of the year."],
        [1, 8, "The Big Bake-Off", "The annual bake-off judge turns out to have no sense of taste."]
    ])
    DS_series(items, "smh", "Strip Mall Heroes", 1994, 22, ["Comedy"], [
        [1, 1, "Grand Opening", "The mall's newest tenant opens on the same day as the parking-lot repaving."],
        [1, 2, "The Food Court Feud", "Two neighboring pretzel stands go to war over a single shared napkin dispenser."],
        [1, 3, "Arcade Fire Drill", "An unscheduled fire drill traps the arcade's high-score holder mid-run."],
        [1, 4, "Mannequin Overboard", "A display mannequin goes missing and every store blames the one next door."],
        [2, 1, "Return Policy", "A customer tries to return an item from a store that closed in 1987."],
        [2, 2, "Escalator Etiquette", "The mall's only escalator breaks and the tenants draft a stair treaty."],
        [2, 3, "The Pretzel Protocol", "A health inspection sends the food court into a cover-up involving one very large pretzel."],
        [2, 4, "Closing Time", "The mall announces new hours, and nobody can agree on which clock is right."]
    ])
    DS_series(items, "p9", "Precinct 9 at Nine", 1991, 44, ["Drama", "Crime"], [
        [1, 1, "Night Shift", "A rookie's first night shift ends with a confession nobody asked for."],
        [1, 2, "Cold Coffee", "A diner robbery goes wrong when the detective on break turns out to be the only customer."],
        [1, 3, "The Pawn Shop Job", "A pawned trumpet leads the squad to a string of burglaries across the precinct."],
        [1, 4, "Internal Affairs", "An internal investigation puts the night shift's favorite sergeant under the lamp."],
        [1, 5, "Dead Drop", "A briefcase left on the number 9 bus has everyone wondering who it was meant for."],
        [1, 6, "Witness", "The only witness to a hit-and-run is a parking attendant who swears he saw nothing."],
        [1, 7, "The Long Stakeout", "Two detectives spend eleven hours in a parked car waiting for a light to turn on."],
        [1, 8, "Badge Number", "A retired officer's badge number turns up on a fresh arrest report."]
    ])
    return items
end function

function DS_series(items as Object, id as String, name as String, year as Integer, mins as Integer, genres as Object, eps as Object)
    for each e in eps
        items.Push(MediaItem_new({id: id + "-s" + iStr(e[0]) + "e" + iStr(e[1]), kind: "episode", title: e[2], seriesTitle: name,
            seriesID: id, season: e[0], episode: e[1], year: year, genres: genres, runtime: mins * 60, overview: e[3],
            contentRating: "TV-PG", libraryID: "demo-tv"}))
    end for
end function
