"""Deterministic browsing groups from Glyph's reviewed descriptions.

Use whole words, never colours or a clip's placeholder palette. Occasion and
game context wins; otherwise the first concrete subject wins over accessories.
An optional authored category in the description overrides these rules.
"""
import re

CATEGORIES = (
    "Classic Cartoons", "Storybook", "Monsters & Legends", "Masterpieces",
    "Chill", "Party", "Emoji", "Love", "Holidays", "Nature", "Animals",
    "Water", "Weather", "Space", "Fire & Energy", "Abstract", "Patterns", "Hypnotic",
    "Retro & Digital", "Gaming", "Science & Sims", "Food & Drink", "Symbols", "Flags",
    "Characters", "People", "Places", "Transport", "Music", "Sports", "Words",
    "Objects", "Other",
)


def words(text):
    return set(re.findall(r"[^\W_]+", text.casefold()))


# Singular/plural forms also cover descriptions written before noun expansion.
SUBJECT_GROUPS = {
    "Animals": "cat cats kitten kittens dog dogs puppy puppies husky corgi rabbit rabbits bunny bunnies mouse mice bird birds duck ducks duckling ducklings owl owls penguin penguins frog frogs fish fishes shark dolphin whale butterfly butterflies bee bees beetle insect insects snail turtle fox foxes wolf wolves lion lions tiger tigers bear bears panda pandas koala koalas elephant giraffe monkey horse horses deer reindeer camel hedgehog hamster pig pigs chick chicks chicken rooster octopus jellyfish crab crabs",
    "Food & Drink": "food fruit apple apples cherry cherries banana bananas strawberry strawberries watermelon lemon lemons orange avocado peach pear grape grapes pineapple burger burgers pizza taco tacos donut donuts doughnut doughnuts cookie cookies cake cakes cupcake cupcakes candy candies popcorn fries sushi ramen noodles egg eggs bread sandwich sandwiches rice coffee tea milk soda beer wine drink drinks cup cups mug mugs bottle bottles",
    "Space": "space planet planets earth globe moon moons star stars starfield astronaut astronauts rocket rockets spacecraft spaceship spaceships satellite satellites ufo ufos galaxy nebula comet meteor saturn",
    "Nature": "nature landscape tree trees forest forests flower flowers blossom blossoms rose roses sunflower sunflowers tulip tulips daisy daisies plant plants cactus cacti leaf leaves mushroom mushrooms mountain mountains hill hills grass garden gardens rainbow rainbows waterfall waterfalls",
    "Water": "water wave waves ocean sea lake lakes river rivers beach beaches sailboat sailboats boat boats ship ships submarine",
    "Weather": "weather cloud clouds rain snow snowflake snowflakes sun suns sunshine lightning storm storms tornado umbrella umbrellas snowman snowmen",
    "Fire & Energy": "fire flame flames lava volcano ember embers explosion explosions bomb bombs energy electricity",
    "Music": "music note notes instrument instruments guitar guitars piano keyboard saxophone trumpet drums drum speaker speakers headphone headphones microphone equalizer cassette record vinyl radio",
    "Sports": "sport sports football soccer basketball baseball tennis volleyball golf athlete athletes jersey racket skateboard surfboard",
    "Transport": "vehicle vehicles car cars truck trucks bus buses train trains locomotive bicycle bike motorcycle scooter airplane aircraft biplane helicopter tractor taxi taxis",
    "Characters": "character characters creature creatures monster monsters robot robots bot bots alien aliens unicorn unicorns dragon dragons vampire vampires zombie zombies skeleton skeletons devil demon demons knight wizard mermaid yeti superhero superheroes",
    "People": "person people man men woman women girl girls boy boys child children baby babies couple couples portrait portraits dancer dancers figure figures stickman human sailor king queen princess prince gymnast",
    "Places": "city cities building buildings house houses castle castles town towns room rooms street streets bridge bridges tower towers cabin cabins shop shops",
    "Objects": "object objects tool tools knife knives scissors screwdriver drill fan meter gauge bag bags backpack handbag shoe shoes sneaker sneakers boot boots shirt shirts clothing garment garments trousers hat hats curtain curtains cigarette toilet clapperboard appliance appliances microwave paperclip lipstick container containers goblet cannon gun guns revolver propeller piston machine machines pumpjack cone cones pipe pipes pedestal necklace feather fence conveyor",
    "Love": "heart hearts love kiss kisses kissing romance couple",
    "Emoji": "face faces smiley emoji emojis expression expressions smile smiles eyes eye tongue tear tears",
    "Words": "text word words letter letters lettering alphabet number numbers digit digits numeral numerals countdown greeting greetings",
    "Flags": "flag flags",
    "Symbols": "symbol symbols emblem emblems logo logos flag flags icon icons arrow arrows cross crosses sign signs badge question exclamation check checkmark battery lock padlock bell crown peace key keys skull skulls",
    "Retro & Digital": "computer computers monitor monitors television tv screen screens console consoles controller controllers joystick handheld calculator phone telephone camera pixel pixels glitch noise code circuit circuits chip chips",
    "Science & Sims": "science atom atoms molecule molecules dna microscope experiment pendulum cradle radar magnet magnets",
    "Party": "party fireworks firework confetti sparkler sparklers disco balloon balloons",
    "Abstract": "abstract pattern patterns shape shapes geometry geometric grid grids tile tiles mosaic mosaics square squares rectangle rectangles circle circles ring rings triangle triangles diamond diamonds spiral spirals tunnel tunnels orb orbs dot dots particle particles speck specks line lines stripe stripes bar bars block blocks cube cubes checkerboard lattice mandala pinwheel loop loops glow gradient kaleidoscope",
}
SUBJECT_GROUPS = {category: set(nouns.split()) for category, nouns in SUBJECT_GROUPS.items()}
SUBJECT_GROUPS["Animals"].update("animal animals bat bats spider spiders snake snakes lizard lizards rat rats llama goat goats dinosaur dinosaurs paw paws turtles axolotl seahorse scorpion crocodile".split())
SUBJECT_GROUPS["Food & Drink"].update("icecream popsicle pudding chocolate sushi sausage hotdog pear pears eggplant pill capsule".split())
SUBJECT_GROUPS["Characters"].update("ghost ghosts witch witches fairy fairies angel angels scarecrow scarecrows skeletons mask masks wand sword trident helmet".split())
SUBJECT_GROUPS["Emoji"].update("hand hands gesture gestures thumb thumbs finger fingers sunglasses glasses".split())
SUBJECT_GROUPS["Symbols"].update("coin coins gem gems jewel jewels hourglass gift gifts ornament bow ribbon target crosshair chest lantern lamp lightbulb pin button shield document scroll teeth tooth yin yang buddha statue torii".split())
SUBJECT_GROUPS["Retro & Digital"].update("clock clocks watch watches floppy disk wifi internet antenna".split())
SUBJECT_GROUPS["Sports"].update("trophy trophies medal medals".split())
SUBJECT_GROUPS["Science & Sims"].update("flask chemical chemistry scale scales balance".split())
SUBJECT_GROUPS["Fire & Energy"].update("spark sparks candle candles campfire".split())
SUBJECT_GROUPS["Words"].update("speech bubble bubbles pencil pen".split())
SUBJECT_GROUPS["Abstract"].update("maze mazes color colour field fields starburst light lights slat slats panel panels beam beams streak streaks band bands trail trails swirl swirls burst bursts arc arcs curve curves wheel wheels disc discs disk discs horn horns blob blobs".split())
SUBJECT_GROUPS["Animals"].update("capybara goose geese ladybug ladybugs squid".split())
SUBJECT_GROUPS["Nature"].update("sunset horizon cave pond lotus aurora".split())
SUBJECT_GROUPS["Water"].update("droplet droplets drop drops splash anchor fishing".split())
SUBJECT_GROUPS["Places"].update("village villages doorway door elevator gateway window arch track railroad skyline".split())
SUBJECT_GROUPS["Objects"].update("barber pole table envelope cauldron scythe film chain beads vase bench pot axe gear box cap top".split())
SUBJECT_GROUPS["Abstract"].update("mesh cylinder cylinders oval ovals dash dashes stroke strokes sphere spheres sunburst rosette chevron corner corners blur outline outlines flow".split())
SUBJECT_GROUPS["Symbols"].update("sparkle sparkles x mark marks wings".split())
SUBJECT_GROUPS["Characters"].update("warrior mage totoro catbus".split())
SUBJECT_GROUPS["Science & Sims"].update("heartbeat waveform thermometer".split())
SUBJECT_GROUPS["Food & Drink"].update("carrot carrots".split())
SUBJECT_GROUPS["Gaming"] = {"dice", "die"}
SUBJECT_GROUPS["Symbols"].update({"pedestrian", "signal"})
SUBJECT_GROUPS["Objects"].update({"toaster", "ball", "platform", "platforms"})
SUBJECT_GROUPS["Water"].add("fountain")
SUBJECT_GROUPS["Characters"].add("slime")
SUBJECT_GROUPS["Emoji"].add("poop")

HOLIDAYS = set("christmas xmas santa halloween pumpkin pumpkins easter valentine valentines hanukkah menorah diwali ramadan eid kwanzaa holiday holidays birthday birthdays wreath stocking mistletoe candycane jackolantern".split())
HOLIDAYS.update({"tombstone", "coffin", "coffins"})
GAMES = set("gaming game games arcade tetris pacman pokemon pikachu pokeball mario luigi kirby sonic minecraft creeper invader invaders pong zelda triforce amongus".split())


def abstract_category(description):
    subjects = set().union(*(words(s) for s in description["subjects"]))
    if subjects & {"spiral", "spirals", "tunnel", "tunnels"}:
        return "Hypnotic"
    if subjects & {"pattern", "patterns", "grid", "grids", "checkerboard", "checkerboards",
                   "mosaic", "mosaics", "lattice", "lattices", "tile", "tiles", "stripe", "stripes"}:
        return "Patterns"
    return "Abstract"


def category_for(description):
    override = description.get("category")
    if override is not None:
        if override not in CATEGORIES:
            raise ValueError(f"Unknown browsing category: {override}")
        return override
    phrases = [description["title"], *description.get("aliases", []),
               *description["subjects"], *description["tags"]]
    context = set().union(*(words(p) for p in phrases))
    joined = " ".join(p.casefold() for p in phrases)
    if context & HOLIDAYS or any(p in joined for p in (
        "new year", "fathers day", "father's day", "mothers day", "mother's day",
        "happy birthday", "candy cane", "jack o lantern", "jack-o-lantern",
    )):
        return "Holidays"
    if context & GAMES or any(p in joined for p in ("tic tac toe", "space invader", "game over", "hollow knight", "among us", "slot machine", "playing card", "chess")):
        return "Gaming"
    if context & {"firework", "fireworks", "confetti", "disco", "party"}:
        return "Party"
    if context & {"painting", "masterpiece", "artwork"}:
        return "Masterpieces"
    # Instruments must not become Words just because their notes scroll.
    if context & {"equalizer", "piano", "guitar", "cassette", "headphones", "saxophone", "sound", "accordion", "audio"} or "tuning fork" in joined:
        return "Music"
    if context & {"trophy", "trophies", "medal", "medals"}:
        return "Sports"
    if "ice cream" in joined:
        return "Food & Drink"
    for subject in description["subjects"]:
        if subject.casefold() == "light bulb":
            return "Symbols"
        if subject.casefold() == "speech bubble":
            return "Words"
        subject_words = words(subject)
        for category, nouns in SUBJECT_GROUPS.items():
            if subject_words & nouns:
                if category == "Water" and subject_words & {"wave", "waves"} and not context & {"water", "ocean", "sea", "river", "lake", "boat", "ship", "sailboat", "beach"}:
                    return abstract_category(description)
                return abstract_category(description) if category == "Abstract" else category
    if context & {"cartoon", "anime", "character", "superhero"}:
        return "Characters"
    if context & {"city", "building", "buildings", "house", "houses", "castle", "town", "room", "street", "bridge", "tower"}:
        return "Places"
    # A missing subject match can still use an explicit style or setting tag.
    for category, nouns in SUBJECT_GROUPS.items():
        if (context - {"orange"}) & nouns:
            return abstract_category(description) if category == "Abstract" else category
    return "Other"
