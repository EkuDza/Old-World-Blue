/obj/mecha_cabin
	name = ""
	var/pass_move = 0
	var/obj/mecha/chasis = null

/obj/mecha_cabin/pilot
	name = "Pilot"

/obj/mecha_cabin/New(var/atom/new_loc)
	..()
	if(istype(new_loc, /obj/mecha)
		chasis = new_loc

/obj/mecha_cabin/relaymove(mob/user,direction)
	if(pass_move && chasis)
		chasis.relaymove(user, direction)
	return 0