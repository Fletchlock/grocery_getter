extends Node


func _ready() -> void:
	print("=== STEAM PEER TEST ===")

	Steam.initRelayNetworkAccess()

	print("Creating first peer...")
	var peer1 := SteamMultiplayerPeer.new()

	var error1 := peer1.create_host(1)
	print("First create_host result: ", error1)

	if error1 != OK:
		print("FIRST HOST FAILED")
		return

	print("Closing first peer...")
	peer1.close()

	print("First peer status after close: ", peer1.get_connection_status())

	await get_tree().process_frame

	print("Creating second peer...")
	var peer2 := SteamMultiplayerPeer.new()

	var error2 := peer2.create_host(1)
	print("Second create_host result: ", error2)

	if error2 != OK:
		print("SECOND HOST FAILED")
	else:
		print("SECOND HOST SUCCEEDED!")

	peer2.close()

	print("=== TEST COMPLETE ===")
