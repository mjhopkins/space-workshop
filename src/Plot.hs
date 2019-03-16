{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DuplicateRecordFields      #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE ScopedTypeVariables        #-}
module Plot where


import qualified Codec.Picture.Png                         as Png
import           Control.Lens                              ((.=))
import           Control.Monad                             (forM_)
import qualified Data.ByteString.Lazy                      as LBS
import           Data.Colour                               (Colour)
import qualified Data.Metrology.Vector                     as DMV
import           Data.String                               (IsString)
import           Data.Text                                 (Text)
import qualified Data.Text                                 as Text
import           Data.VectorSpace                          (Scalar, VectorSpace)
import qualified Diagrams.Backend.Rasterific               as BR
import           Diagrams.Prelude                          (( # ))
import qualified Diagrams.Prelude                          as D
import qualified Graphics.Rendering.Chart.Backend.Diagrams as Chart
import qualified Graphics.Rendering.Chart.Easy             as Chart
import qualified ITermShow
import           System.IO                                 (stdout)


data Output
  = Screen
  | PNG FilePath
  | SVG FilePath


data XYChart
  = XYChart
    { title      :: !Title
    , xLabel     :: !XLabel
    , yLabel     :: !YLabel
    , chartItems :: [Item Double Double]
    }
newtype Title = Title { unTitle :: Text } deriving (IsString)
newtype XLabel = XLabel { unXLabel :: Text } deriving (IsString)
newtype YLabel = YLabel { unYLabel :: Text } deriving (IsString)
data Item x y
  = Line Text [(x, y)]
  | Points Text [(x, y)]


xyChartUnits
  :: forall dimx dimy unitx unity l.
     ( DMV.ValidDLU dimx l unitx
     , DMV.ValidDLU dimy l unity )
  => Output
  -> Title
  -> XLabel
  -> YLabel
  -> (unitx, unity)
  -> [Item (DMV.Qu dimx l Double) (DMV.Qu dimy l Double)]
  -> IO ()
xyChartUnits out t x y (ux, uy) items
  = xyChart out t x y (itemInUnits (ux, uy) <$> items)


itemInUnits
  :: forall dimx dimy unitx unity l n.
     ( DMV.ValidDLU dimx l unitx
     , DMV.ValidDLU dimy l unity
     , VectorSpace n, Fractional (Scalar n) )
  => (unitx, unity)
  -> Item (DMV.Qu dimx l n) (DMV.Qu dimy l n)
  -> Item n n
itemInUnits (ux, uy) item =
  let
    inu (x, y) = (x DMV.# ux, y DMV.# uy)
  in
    case item of
      Line t xys   -> Line t (inu <$> xys)
      Points t xys -> Points t (inu <$> xys)


xyChart
  :: Output
  -> Title
  -> XLabel
  -> YLabel
  -> [Item Double Double]
  -> IO ()
xyChart out t x y items =
  let
    chart = XYChart t x y items
  in case out of
       Screen -> do
         png <- plotXYChartPNGBS chart
         LBS.hPutStr stdout (ITermShow.displayImage png)
         putStrLn ""
       PNG _ -> error "Not yet implemented"
       SVG _ -> error "Not yet implemented"


plotXYChartPNGBS :: XYChart -> IO LBS.ByteString
plotXYChartPNGBS chart = do
  env <- Chart.defaultEnv Chart.vectorAlignmentFns 500 375
  let dia = fst $ Chart.runBackendR env (Chart.toRenderable (xyChartEC chart))
  let img = BR.rasterRgb8 (D.mkWidth 1600) dia
  pure (Png.encodePng img)


xyChartEC :: XYChart -> Chart.Renderable ()
xyChartEC chart = Chart.toRenderable $ do
  Chart.layout_title .= (Text.unpack . unTitle . title $ chart)
  Chart.layout_x_axis . Chart.laxis_title .=
    (Text.unpack . unXLabel . xLabel $ chart)
  Chart.layout_y_axis . Chart.laxis_title .=
    (Text.unpack . unYLabel . yLabel $ chart)
  forM_ (chartItems chart) $ \case
    Line label pts -> Chart.plot (Chart.line (Text.unpack label) [pts])
    Points label pts -> Chart.plot (Chart.points (Text.unpack label) pts)


data OrbitSystem
  = OrbitSystem
    { systemItems :: [OrbitSystemItem] }
data OrbitSystemItem
  = Planet { radius :: Double, color :: Colour Double }
  | Trajectory { points :: [(Double, Double)], color :: Colour Double }


plotOrbitSystem :: Output -> OrbitSystem -> IO ()
plotOrbitSystem output system =
  case output of
    Screen -> do
      let png = plotOrbitSystemPNGBS system
      LBS.hPutStr stdout (ITermShow.displayImage png)
      putStrLn ""
    PNG _ -> error "Not yet implemented"
    SVG _ -> error "Not yet implemented"


plotOrbitSystemPNGBS :: OrbitSystem -> LBS.ByteString
plotOrbitSystemPNGBS system =
  let
    dia = mconcat (plotSystemItem <$> systemItems system)
    img = BR.rasterRgb8 (D.dims2D 1600 1200) dia
  in
    Png.encodePng img


plotSystemItem :: OrbitSystemItem -> D.Diagram BR.B
plotSystemItem (Planet r c)
  = D.circle r # D.fc c
plotSystemItem (Trajectory pts c)
  = D.fromVertices (D.p2 <$> pts) # D.lc c