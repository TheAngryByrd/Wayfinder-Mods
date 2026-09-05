import unreal


ASSET_ROOT = "/Game/Mods/Loadouts"
UI_ROOT = ASSET_ROOT + "/UI"


def create_actor_blueprint():
    asset_path = ASSET_ROOT + "/ModActor"
    if unreal.EditorAssetLibrary.does_asset_exist(asset_path):
        return
    factory = unreal.BlueprintFactory()
    factory.set_editor_property("parent_class", unreal.Actor)
    asset = unreal.AssetToolsHelpers.get_asset_tools().create_asset(
        "ModActor", ASSET_ROOT, unreal.Blueprint, factory
    )
    if asset is None:
        raise RuntimeError("Unable to create ModActor.")


def create_widget_blueprint(name):
    asset_path = UI_ROOT + "/" + name
    if unreal.EditorAssetLibrary.does_asset_exist(asset_path):
        return
    factory = unreal.WidgetBlueprintFactory()
    factory.set_editor_property("parent_class", unreal.UserWidget)
    asset = unreal.AssetToolsHelpers.get_asset_tools().create_asset(
        name, UI_ROOT, unreal.WidgetBlueprint, factory
    )
    if asset is None:
        raise RuntimeError("Unable to create " + name + ".")


unreal.EditorAssetLibrary.make_directory(ASSET_ROOT)
unreal.EditorAssetLibrary.make_directory(UI_ROOT)
create_actor_blueprint()
create_widget_blueprint("WBP_LoadoutsPage")
create_widget_blueprint("WBP_LoadoutProfileRow")
create_widget_blueprint("WBP_LoadoutNameDialog")
unreal.EditorAssetLibrary.save_directory(ASSET_ROOT, only_if_is_dirty=False, recursive=True)

required_assets = [
    ASSET_ROOT + "/ModActor",
    UI_ROOT + "/WBP_LoadoutsPage",
    UI_ROOT + "/WBP_LoadoutProfileRow",
    UI_ROOT + "/WBP_LoadoutNameDialog",
]
for required_asset in required_assets:
    if not unreal.EditorAssetLibrary.does_asset_exist(required_asset):
        raise RuntimeError("Generated asset is missing: " + required_asset)

unreal.log("Loadouts UMG assets are ready.")
