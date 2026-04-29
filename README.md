# NIRC2-Pol Operations Software

Last Updated: 29 April 2026

NIRC2 Polarimetry (NIRC2-Pol, or nirc2p) is a dual-channel polarimetry mode on the Keck II NIRC2 infrared imager. Dual-channel polarimetry uses a polarizing beamsplitter to split the incoming light into two orthogonal polarization states, and a half-wave plate (HWP) to modulate the angle of polarization. Through cycles of four critical HWP angles (0°, 45°, 22.5°, 67.5°), it is possible to recover the linear Stokes vector components Q and U (see de Boer+ 2020 for a description of dual-channel polarimetry and double differencing). 

NIRC2-Pol enables polarimetric observations in JHKL’ bands in combination with multiple existing NIRC2 modes, such as grism spectroscopy and high-contrast coronagraphic imaging, and both NGS and LGS AO. This is useful for many science cases, from solar system objects to circumstellar disks and active galactic nuclei. NIRC2-Pol was developed as part of the Precision Calibration Unit (PCU2) project on Keck II. 

**About this repository**

This repository contains scripts for efficiently operating the NIRC2 Polarimetry mode. The most officially up-to-date versions of operations scripts will soon be transferred to and managed with Keck's internal SVN version control, where observatory staff will maintain them. Other repositories ([NIRC2-DPP](https://github.com/UCSB-Exoplanet-Polarimetry-Lab/NIRC2Pol-DPP), [pyPolCal](https://github.com/UCSB-Exoplanet-Polarimetry-Lab/pyPolCal)) contain code related to data processing for the mode and instrumental polarization calibration.

**Files in this repo**

- [Folder] Commissioning Analysis = Various files and scripts from use in commissioning; kept as a "historical record"

**Operations/Observer's Guide**

A [draft version of the NIRC2-Pol operations/observer's guide](https://docs.google.com/document/d/1xZ5t1CYUM9_GUHD_lKeaxhGwf5xAPUc301j2dv2oiKI/edit?tab=t.v9hqfo1pspp7#heading=h.ej8cynj3sfoq) is available.

**Citation and Acknowledgements**

To acknowledge the use of the NIRC2 Polarimetry mode, including code from this repo, please cite Lewis et al. in prep (the NIRC2-Pol first light paper). See below for a BibTeX entry, which will be soon updated.
```
@article{lewis2026nirc,
  title={NIRC2-Pol: First Light of Near-Infrared Polarimetry on Keck II},
  author={Lewis, Briley L. and Zhang, Rebecca and Millar-Blanchaer, Maxwell and Marin, Eduardo and Nguyen, Jayke and Melby, William and others},
  year={In Prep.}
}
```

If using the NIRC2-Pol DPP and/or the Mueller matrix model of the instrument (both currently under development), there will be SPIE proceedings for those coming Summer 2026--Lewis et al. 2026 and Zhang et al. 2026, respectively.

NIRC2-Pol PI: Max Millar-Blanchaer (UCSB)
NIRC2-Pol Team: Rebecca Zhang, Briley Lewis (UCSB); Jayke Nguyen (UCSD), Ryan Hersey (UCSB), Will Melby (U of A), Thomas McIntosh (UCSB), Mike Fitzgerald (UCLA), Dimitri Mawet (Caltech), Nem Jovanovic (Caltech), Keith Matthews (Caltech)
PCU2 Team: Jessica Lu, Charles-Antoine Claveau, Matthew Freeman (Berkeley); Eduardo Marin, Scott Lilley, Ed Wetherell, Jacob Taylor, Mahawa Cisse, Lauren Simmons, Paul Richards, Carlos Alvarez, Percy Gomez, Kittrin Matthews, Max Service, Trisha Harmmen, Jim Lyke (Keck)

