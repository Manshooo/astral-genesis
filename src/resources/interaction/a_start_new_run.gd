class_name A_StartNewRun
extends RS_InteractionAction

func execute(_entity: Entity, _interactor: Node = null) -> void:
	RunManager.enter_complex()
