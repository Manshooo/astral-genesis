class_name A_FinishRun
extends RS_InteractionAction

func execute(_entity: Entity, _interactor: Node = null) -> void:
	RunManager.finish_run()
