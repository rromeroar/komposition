{-# OPTIONS_GHC -fno-warn-unticked-promoted-constructors #-}

{-# LANGUAGE ConstraintKinds   #-}
{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE GADTs             #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedLabels  #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds         #-}
{-# LANGUAGE RankNTypes        #-}
{-# LANGUAGE RebindableSyntax  #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TypeOperators     #-}
module FastCut.Application.ImportMode where

import           FastCut.Application.Base

import           Control.Lens
import           Data.String                              ( fromString )

import           FastCut.Focus
import           FastCut.Import.FFmpeg
import           FastCut.Library
import           FastCut.MediaType
import           FastCut.Project

import           FastCut.Application.KeyMaps

data ImportFileForm = ImportFileForm
  { selectedFile :: Maybe FilePath
  , autoSplit    :: Bool
  }

importFile
  :: Application t m
  => Name n
  -> Project
  -> Focus ft
  -> ThroughMode TimelineMode ImportMode (t m) n Project
importFile gui project focus' = do
  enterImport gui
  f <- fillForm ImportFileForm {selectedFile = Nothing, autoSplit = False}
  returnToTimeline gui project focus'
  maybe (ireturn project) (importAsset gui project) f
 where
  fillForm mf = do
    cmd <- nextEvent gui
    case (cmd, mf) of
      (CommandKeyMappedEvent Cancel, _) -> ireturn Nothing
      (CommandKeyMappedEvent Help  , _) -> do
        help gui [ModeKeyMap SImportMode (keymaps SImportMode)]
        fillForm mf
      (ImportClicked, ImportFileForm { selectedFile = Just file, ..}) ->
        ireturn (Just (file, autoSplit))
      (ImportClicked, form) -> fillForm form
      (ImportFileSelected file, form) ->
        fillForm (form { selectedFile = file })
      (ImportAutoSplitSet s, form) -> fillForm (form { autoSplit = s })

data Ok = Ok deriving (Eq, Enum)

instance DialogChoice Ok where
  toButtonLabel Ok = "OK"

importAsset
  :: (UserInterface m, IxMonadIO m)
  => Name n
  -> Project
  -> (FilePath, Bool)
  -> Actions m '[n := Remain (State m TimelineMode)] r Project
importAsset gui project (filepath, True)
  = progressBar
      gui
      "Import Video"
      (importVideoFileAutoSplit filepath (project ^. workingDirectory))
    >>>= \case
           Nothing -> do
             iliftIO (putStrLn ("No result." :: Text))
             ireturn project
           Just assets -> handleImportResult gui project SVideo assets
importAsset gui project (filepath, False) =
  progressBar gui
              "Import Video"
              (importVideoFile filepath (project ^. workingDirectory))
    >>>= \case
           Nothing    -> ireturn project
           Just asset -> handleImportResult gui project SVideo (fmap pure asset)

handleImportResult
  :: (UserInterface m, IxMonadIO m, Show err)
  => Name n
  -> Project
  -> SMediaType mt
  -> Either err [Asset mt]
  -> Actions m '[n := Remain (State m TimelineMode)] r Project
handleImportResult gui project mediaType result =
  case (mediaType, result) of
    (_, Left err) -> do
      iliftIO (print err)
      _ <- dialog gui "Import Failed!" (show err) [Ok]
      ireturn project
    (SVideo, Right assets) -> do
      project & library . videoAssets %~ (<> assets) & ireturn
    (SAudio, Right assets) -> do
      project & library . audioAssets %~ (<> assets) & ireturn